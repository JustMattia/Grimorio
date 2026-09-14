import { parse } from "csv-parse/sync";
import fs from "fs";
import path from "path";

const INCOMING_DIR = "../incoming";
const DATA_PATH = "../data/cards.json";

// Dizionario MTG ufficiale inglese -> italiano per tipi e sottotipi
const DIZIONARIO_TIPI = {
  "Creature": "Creatura",
  "Artifact": "Artefatto",
  "Enchantment": "Incantesimo",
  "Instant": "Istantaneo",
  "Sorcery": "Stregoneria",
  "Land": "Terra",
  "Planeswalker": "Planeswalker",
  "Battle": "Battaglia",
  "Tribal": "Tribale",
  "Kindred": "Affine",
  "Legendary": "Leggendario",
  "Basic": "Base",
  "Snow": "Neve",
  "World": "Mondo",
  "Aura": "Aura",
  "Equipment": "Equipaggiamento",
  "Vehicle": "Veicolo",
  "Saga": "Saga",
  "Trap": "Trappola",
  "Siege": "Assedio",
  "Human": "Umano",
  "Elf": "Elfo",
  "Goblin": "Goblin",
  "Zombie": "Zombie",
  "Wizard": "Mago",
  "Warrior": "Guerriero",
  "Soldier": "Soldato",
  "Knight": "Cavaliere",
  "Cleric": "Chierico",
  "Rogue": "Furfante",
  "Shaman": "Sciamano",
  "Druid": "Druido",
  "Bird": "Uccello",
  "Insect": "Insetto",
  "Beast": "Bestia",
  "Dragon": "Drago",
  "Angel": "Angelo",
  "Demon": "Demone",
  "Vampire": "Vampiro",
  "Spider": "Ragno",
  "Snake": "Serpente",
  "Cat": "Gatto",
  "Wolf": "Lupo",
  "Bear": "Orso",
  "Fish": "Pesce",
  "Merfolk": "Tritone",
  "Spirit": "Spirito",
  "Elemental": "Elementale",
  "Giant": "Gigante",
  "Golem": "Golem",
  "Treefolk": "Silvantropo",
  "Dwarf": "Nano",
  "Phyrexian": "Phyrexiano",
  "Sliver": "Tramutante",
  "Faerie": "Fata",
  "Horror": "Orrore",
  "Nightmare": "Incubo",
  "Urza's Tower": "Torre di Urza",
  "Urza's Mine": "Miniera di Urza",
  "Urza's Power-Plant": "Centrale Energetica di Urza",
  "Plains": "Pianura",
  "Island": "Isola",
  "Swamp": "Palude",
  "Mountain": "Montagna",
  "Forest": "Foresta"
};

function traduciTipo(tipoInglese) {
  if (!tipoInglese) return "";
  let str = tipoInglese.trim();
  const strLow = str.toLowerCase();
  if (strLow.includes("creatura") || strLow.includes("stregoneria") || strLow.includes("istantaneo") || strLow.includes("incantesimo") || strLow.includes("artefatto") || strLow.includes("terra")) {
    return str;
  }
  const parts = str.split(/\s+[—–-]\s+/);
  let tradMain = parts[0]
    .replace(/Legendary Artifact Creature/g, "Creatura Artefatto Leggendaria")
    .replace(/Legendary Enchantment Creature/g, "Creatura Incantesimo Leggendaria")
    .replace(/Legendary Creature/g, "Creatura Leggendaria")
    .replace(/Legendary Artifact/g, "Artefatto Leggendario")
    .replace(/Legendary Enchantment/g, "Incantesimo Leggendario")
    .replace(/Legendary Land/g, "Terra Leggendaria")
    .replace(/Legendary Planeswalker/g, "Planeswalker Leggendario")
    .replace(/Artifact Creature/g, "Creatura Artefatto")
    .replace(/Enchantment Creature/g, "Creatura Incantesimo")
    .replace(/Basic Land/g, "Terra Base")
    .replace(/Basic Snow Land/g, "Terra Neve Base")
    .replace(/Snow Land/g, "Terra Neve")
    .replace(/Tribal Sorcery/g, "Stregoneria Tribale")
    .replace(/Tribal Instant/g, "Istantaneo Tribale")
    .replace(/Tribal Enchantment/g, "Incantesimo Tribale")
    .replace(/Kindred Sorcery/g, "Stregoneria Affine")
    .replace(/Kindred Instant/g, "Istantaneo Affine")
    .replace(/Kindred Enchantment/g, "Incantesimo Affine");

  for (const [en, it] of Object.entries(DIZIONARIO_TIPI)) {
    const regex = new RegExp(`\\b${en}\\b`, "g");
    tradMain = tradMain.replace(regex, it);
  }

  if (!parts[1]) return tradMain;

  let tradSub = parts[1];
  for (const [en, it] of Object.entries(DIZIONARIO_TIPI)) {
    const regex = new RegExp(`\\b${en}\\b`, "g");
    tradSub = tradSub.replace(regex, it);
  }
  return `${tradMain} — ${tradSub}`;
}

// --- 1. Trova i CSV in attesa di essere importati ---

const fileDaImportare = fs.existsSync(INCOMING_DIR)
  ? fs.readdirSync(INCOMING_DIR).filter((f) => f.endsWith(".csv"))
  : [];

if (fileDaImportare.length === 0) {
  console.log("Nessun CSV da importare.");
  process.exit(0);
}

// --- 2. Scryfall, a blocchi da 75: dà nome, immagine e anche il prezzo EUR
//        (quel prezzo è aggiornato quotidianamente da Scryfall a partire da
//        Cardmarket, quindi non serve una chiamata separata a Cardmarket) ---

async function scryfallCollection(scryfallIds) {
  const identifiers = scryfallIds.map((id) => ({ id }));
  const res = await fetch("https://api.scryfall.com/cards/collection", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "User-Agent": "la-dispensa/1.0",
    },
    body: JSON.stringify({ identifiers }),
  });
  const data = await res.json();
  if (!res.ok) {
    console.error(`Scryfall ha risposto ${res.status}:`, JSON.stringify(data));
    return [];
  }
  if (data.not_found?.length) {
    console.warn(
      "Scryfall non ha trovato questi ID:",
      JSON.stringify(data.not_found),
    );
  }
  console.log(
    `Scryfall: richiesti ${identifiers.length}, trovati ${data.data?.length || 0}`,
  );
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
  if (!process.env.CARDTRADER_TOKEN) {
    console.warn("CARDTRADER_TOKEN non impostato: salto i prezzi Cardtrader.");
    return null;
  }
  try {
    const res = await fetch(`https://api.cardtrader.com/api/v2${percorso}`, {
      headers: { Authorization: `Bearer ${process.env.CARDTRADER_TOKEN}` },
    });
    const data = await res.json();
    if (!res.ok) {
      console.error(
        `Cardtrader ha risposto ${res.status} su ${percorso}:`,
        JSON.stringify(data),
      );
      return null;
    }
    return data;
  } catch (e) {
    console.error(`Errore di rete verso Cardtrader (${percorso}):`, e.message);
    return null;
  }
}

async function findBlueprintId(cardName, setCode) {
  if (ctCache.expansions === null) {
    ctCache.expansions = (await cardtraderRequest("/expansions")) || [];
  }
  const expansion = ctCache.expansions.find(
    (e) => e.code?.toLowerCase() === setCode.toLowerCase(),
  );
  if (!expansion) return null;

  if (!ctCache.blueprintsByExpansion[expansion.id]) {
    ctCache.blueprintsByExpansion[expansion.id] =
      (await cardtraderRequest(
        `/blueprints/export?expansion_id=${expansion.id}`,
      )) || [];
  }
  const blueprint = ctCache.blueprintsByExpansion[expansion.id].find(
    (b) => b.name?.toLowerCase() === cardName.toLowerCase(),
  );
  return blueprint ? blueprint.id : null;
}

async function cardtraderZeroLowPrice(cardName, setCode) {
  const blueprintId = await findBlueprintId(cardName, setCode);
  if (!blueprintId) return null;

  const data = await cardtraderRequest(
    `/marketplace/products?blueprint_id=${blueprintId}`,
  );
  const prodotti = (data && data[blueprintId]) || [];
  // TODO: sostituisci con il campo reale che identifica i venditori Zero
  const zero = prodotti.filter((p) => p.can_sell_via_hub || p.seller?.zero);
  const lista = zero.length ? zero : prodotti;
  const prezzi = lista.map((p) => p.price_cents / 100);
  return prezzi.length ? Math.min(...prezzi) : null;
}

const ctPriceCache = new Map();
const itInfoCache = new Map();

async function getCardtraderPriceCached(cardName, setCode) {
  const key = `${cardName.toLowerCase()}__${setCode.toLowerCase()}`;
  if (ctPriceCache.has(key)) return ctPriceCache.get(key);
  const price = await cardtraderZeroLowPrice(cardName, setCode);
  ctPriceCache.set(key, price);
  return price;
}

async function getItalianCardInfoCached(card) {
  if (itInfoCache.has(card.id)) return itInfoCache.get(card.id);

  let nomeItaliano = card.name;
  let tipoItaliano = null;

  try {
    const resIt = await fetch(`https://api.scryfall.com/cards/${card.set}/${card.collector_number}/it`, {
      headers: { "User-Agent": "Grimorio/1.0" }
    });
    if (resIt.ok) {
      const itData = await resIt.json();
      if (itData) {
        if (itData.printed_name) nomeItaliano = itData.printed_name;
        if (itData.printed_type_line) tipoItaliano = itData.printed_type_line;
      }
    } else {
      // Fallback: se il set specifico non ha edizione italiana (es. Duel Decks), cerca la carta in italiano in altri set
      const q = encodeURIComponent(`!"${card.name}" lang:it`);
      const resSearch = await fetch(`https://api.scryfall.com/cards/search?q=${q}`, {
        headers: { "User-Agent": "Grimorio/1.0" }
      });
      if (resSearch.ok) {
        const searchData = await resSearch.json();
        const itCard = searchData?.data?.[0];
        if (itCard) {
          if (itCard.printed_name) nomeItaliano = itCard.printed_name;
          if (itCard.printed_type_line) tipoItaliano = itCard.printed_type_line;
        }
      }
    }
  } catch (e) {}

  const result = { nomeItaliano, tipoItaliano };
  itInfoCache.set(card.id, result);
  return result;
}

// Helper per elaborazione parallela controllata
async function mapConcurrent(items, limit, asyncFn) {
  const results = new Array(items.length);
  let index = 0;
  async function worker() {
    while (index < items.length) {
      const i = index++;
      results[i] = await asyncFn(items[i], i);
    }
  }
  const workers = Array.from({ length: Math.min(limit, items.length) }, () => worker());
  await Promise.all(workers);
  return results;
}

// --- 4. Elabora ogni file in incoming/ e aggiorna il database condiviso ---

const esistenti = fs.existsSync(DATA_PATH)
  ? JSON.parse(fs.readFileSync(DATA_PATH, "utf8"))
  : [];

for (const nomeFile of fileDaImportare) {
  const possessore = decodeURIComponent(nomeFile.split("__")[0]).replace(
    /-/g,
    " ",
  );
  const csvText = fs.readFileSync(path.join(INCOMING_DIR, nomeFile), "utf8");
  const rows = parse(csvText, { columns: true, skip_empty_lines: true });

  const scryfallIds = [
    ...new Set(rows.map((r) => r["Scryfall ID"]).filter(Boolean)),
  ];
  const cardsById = {};
  for (let i = 0; i < scryfallIds.length; i += 75) {
    const batch = scryfallIds.slice(i, i + 75);
    const results = await scryfallCollection(batch);
    for (const c of results) cardsById[c.id] = c;
    await new Promise((r) => setTimeout(r, 100)); // rispetta il rate limit di Scryfall
  }

  // Elaborazione parallela delle righe a blocchi di 6 concorrenti
  const elaborate = await mapConcurrent(rows, 6, async (row) => {
    const card = cardsById[row["Scryfall ID"]];
    if (!card) {
      console.warn(
        `Nessuna corrispondenza Scryfall per la riga: ${row["Name"]} (${row["Scryfall ID"]})`,
      );
      return null;
    }

    const isFoil = row["Foil"] === "foil";
    const rawLang = row["Language"] || row["language"] || "English";
    const prezzoEur = isFoil ? card.prices?.eur_foil : card.prices?.eur;
    const prezzoCardmarket = prezzoEur ? parseFloat(prezzoEur) : null;

    // Recupero parallelo di prezzo Cardtrader e traduzione italiana
    const [prezzoCardtrader, itInfo] = await Promise.all([
      getCardtraderPriceCached(card.name, card.set),
      getItalianCardInfoCached(card)
    ]);

    const tipoOriginale =
      card.type_line ||
      card.card_faces?.map((f) => f.type_line).filter(Boolean).join(" // ") ||
      "";

    let nomeItaliano = itInfo.nomeItaliano || card.name;
    let tipoItaliano = itInfo.tipoItaliano || traduciTipo(tipoOriginale);

    return {
      scryfallId: card.id,
      nome: nomeItaliano,
      nomeIt: nomeItaliano,
      nomeEn: card.name,
      lingua: rawLang,
      set: card.set,
      numero: card.collector_number,
      immagine:
        card.image_uris?.normal ||
        card.card_faces?.[0]?.image_uris?.normal ||
        null,
      manaCost:
        card.mana_cost ||
        card.card_faces?.map((f) => f.mana_cost).filter(Boolean).join(" // ") ||
        "",
      cmc: card.cmc ?? 0,
      tipo: tipoOriginale,
      tipoIt: tipoItaliano || tipoOriginale,
      colori:
        card.colors ||
        card.card_faces?.[0]?.colors ||
        [],
      rarita: card.rarity || "",
      foil: isFoil,
      quantita: parseInt(row["Quantity"] || "1", 10),
      possessore,
      prezzoCardmarket,
      prezzoCardtrader,
      aggiornatoIl: new Date().toISOString(),
    };
  });

  const carteAggiunte = elaborate.filter(Boolean);
  esistenti.push(...carteAggiunte);

  fs.rmSync(path.join(INCOMING_DIR, nomeFile));
  console.log(
    `${nomeFile}: ${rows.length} righe nel CSV, ${carteAggiunte.length} carte aggiunte per ${possessore}.`,
  );
}

fs.mkdirSync("../data", { recursive: true });
fs.writeFileSync(DATA_PATH, JSON.stringify(esistenti, null, 2));
