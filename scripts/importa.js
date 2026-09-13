import { parse } from 'csv-parse/sync';
import fs from 'fs';
import path from 'path';

const INCOMING_DIR = '../incoming';
const DATA_PATH = '../data/cards.json';

// --- 1. Trova i CSV in attesa di essere importati ---

const fileDaImportare = fs.existsSync(INCOMING_DIR)
  ? fs.readdirSync(INCOMING_DIR).filter((f) => f.endsWith('.csv'))
  : [];

if (fileDaImportare.length === 0) {
  console.log('Nessun CSV da importare.');
  process.exit(0);
}

// --- 2. Scryfall, a blocchi da 75: dà nome, immagine e anche il prezzo EUR
//        (quel prezzo è aggiornato quotidianamente da Scryfall a partire da
//        Cardmarket, quindi non serve una chiamata separata a Cardmarket) ---

async function scryfallCollection(scryfallIds) {
  const identifiers = scryfallIds.map((id) => ({ id }));
  const res = await fetch('https://api.scryfall.com/cards/collection', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identifiers })
  });
  const data = await res.json();
  return data.data || [];
}

// --- 3. Prezzo minimo Cardtrader tra i venditori "Zero" ---
//
// NOTA: il campo esatto che identifica un'offerta CardTrader Zero nella
// risposta di /marketplace/products va confermato ispezionando una risposta
// reale (o la documentazione su cardtrader.com/docs/api): è marcato con TODO.
// Finché non è confermato, viene usato il prezzo più basso in assoluto.

const ctCache = { expansions: null, blueprintsByExpansion: {} };

async function cardtraderRequest(percorso) {
  const res = await fetch(`https://api.cardtrader.com/api/v2${percorso}`, {
    headers: { Authorization: `Bearer ${process.env.CARDTRADER_TOKEN}` }
  });
  return res.json();
}

async function findBlueprintId(cardName, setCode) {
  if (!ctCache.expansions) {
    ctCache.expansions = await cardtraderRequest('/expansions');
  }
  const expansion = ctCache.expansions.find(
    (e) => e.code?.toLowerCase() === setCode.toLowerCase()
  );
  if (!expansion) return null;

  if (!ctCache.blueprintsByExpansion[expansion.id]) {
    ctCache.blueprintsByExpansion[expansion.id] = await cardtraderRequest(
      `/blueprints/export?expansion_id=${expansion.id}`
    );
  }
  const blueprint = ctCache.blueprintsByExpansion[expansion.id].find(
    (b) => b.name?.toLowerCase() === cardName.toLowerCase()
  );
  return blueprint ? blueprint.id : null;
}

async function cardtraderZeroLowPrice(cardName, setCode) {
  const blueprintId = await findBlueprintId(cardName, setCode);
  if (!blueprintId) return null;

  const data = await cardtraderRequest(`/marketplace/products?blueprint_id=${blueprintId}`);
  const prodotti = data[blueprintId] || [];
  // TODO: sostituisci con il campo reale che identifica i venditori Zero
  const zero = prodotti.filter((p) => p.can_sell_via_hub || p.seller?.zero);
  const lista = zero.length ? zero : prodotti;
  const prezzi = lista.map((p) => p.price_cents / 100);
  return prezzi.length ? Math.min(...prezzi) : null;
}

// --- 4. Elabora ogni file in incoming/ e aggiorna il database condiviso ---

const esistenti = fs.existsSync(DATA_PATH) ? JSON.parse(fs.readFileSync(DATA_PATH, 'utf8')) : [];

for (const nomeFile of fileDaImportare) {
  const possessore = decodeURIComponent(nomeFile.split('__')[0]).replace(/-/g, ' ');
  const csvText = fs.readFileSync(path.join(INCOMING_DIR, nomeFile), 'utf8');
  const rows = parse(csvText, { columns: true, skip_empty_lines: true });

  const scryfallIds = [...new Set(rows.map((r) => r['Scryfall ID']).filter(Boolean))];
  const cardsById = {};
  for (let i = 0; i < scryfallIds.length; i += 75) {
    const batch = scryfallIds.slice(i, i + 75);
    const results = await scryfallCollection(batch);
    for (const c of results) cardsById[c.id] = c;
    await new Promise((r) => setTimeout(r, 100)); // rispetta il rate limit di Scryfall
  }

  for (const row of rows) {
    const card = cardsById[row['Scryfall ID']];
    if (!card) continue;

    const isFoil = row['Foil'] === 'foil';
    const prezzoEur = isFoil ? card.prices?.eur_foil : card.prices?.eur;
    const prezzoCardmarket = prezzoEur ? parseFloat(prezzoEur) : null;
    const prezzoCardtrader = await cardtraderZeroLowPrice(card.name, card.set);

    esistenti.push({
      scryfallId: card.id,
      nome: card.name,
      set: card.set,
      numero: card.collector_number,
      immagine: card.image_uris?.normal || card.card_faces?.[0]?.image_uris?.normal || null,
      foil: isFoil,
      quantita: parseInt(row['Quantity'] || '1', 10),
      possessore,
      prezzoCardmarket,
      prezzoCardtrader,
      aggiornatoIl: new Date().toISOString()
    });
  }

  fs.rmSync(path.join(INCOMING_DIR, nomeFile));
  console.log(`Importate ${rows.length} righe per ${possessore} da ${nomeFile}.`);
}

fs.mkdirSync('../data', { recursive: true });
fs.writeFileSync(DATA_PATH, JSON.stringify(esistenti, null, 2));
