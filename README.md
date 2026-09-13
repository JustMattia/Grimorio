# La dispensa — collezione MTG condivisa

Sito statico (GitHub Pages) + GitHub Actions come "backend": si carica un CSV
esportato da ManaBox direttamente dal sito, un workflow lo elabora e
aggiorna la pagina con immagine, possessore e prezzi minimi da Cardmarket
(via Scryfall) e Cardtrader.

## Un avviso prima di iniziare

GitHub Pages gratuito richiede un repository **pubblico** (quello privato
serve un piano a pagamento), e anche il piano a pagamento pubblica comunque
un sito raggiungibile da chiunque abbia il link — non esiste un vero muro
di accesso gratuito lato GitHub. Per tre amici che condividono una lista di
carte non è un problema serio, ma è bene saperlo: chiunque trovasse l'URL
del sito potrebbe vedere la vostra collezione e i valori stimati.

## Setup (una tantum)

1. **Crea un repository pubblico** su GitHub e caricaci dentro tutti questi
   file.

2. **Modifica `index.html`**: in cima allo script, sostituisci
   `INSERISCI-USERNAME` e `INSERISCI-NOME-REPO` con il tuo username GitHub
   e il nome del repository.

3. **Aggiungi il secret** in *Settings → Secrets and variables → Actions →
   New repository secret*:
   - `CARDTRADER_TOKEN` — token Bearer dal tuo account Cardtrader (Cardmarket
     non serve più: il prezzo arriva da Scryfall, vedi sotto)

4. **Attiva GitHub Pages**: *Settings → Pages → Deploy from branch →
   main / (root)*.

5. **Aggiungi i tuoi amici come collaboratori**: *Settings → Collaborators
   → Add people* (serve perché dovranno creare un loro token per poter
   caricare — vedi sotto).

## Uso

1. Scansiona le carte in ManaBox, poi Collezione → menu in alto a destra →
   **Esporta CSV**
2. Apri il sito, scrivi il tuo nome, scegli il file CSV, premi **Carica**
3. La prima volta il sito ti chiede un token GitHub (vedi sotto come
   crearlo): resta salvato solo nel tuo browser, non viene mai scritto nel
   sito o nel repository
4. Entro un minuto o due il workflow elabora il file e la pagina si
   aggiorna — basta ricaricarla

### Creare il proprio token (ogni amico il suo, una volta sola)

GitHub → icona profilo → **Settings** → **Developer settings** →
**Personal access tokens** → **Fine-grained tokens** → **Generate new
token**:
- *Repository access*: **Only select repositories** → scegli questo repo
- *Permissions* → **Contents**: **Read and write**
- Nessun altro permesso serve

Copia il token e incollalo quando il sito lo richiede al primo caricamento.

## Cose da verificare

`scripts/importa.js` ha un `TODO`: il campo che identifica un'offerta
**CardTrader Zero** nella risposta di `/marketplace/products` va confermato
guardando una risposta reale (o la
[documentazione](https://www.cardtrader.com/docs/api)) una volta che hai il
token. Finché non è confermato, lo script usa il prezzo più basso in
assoluto su Cardtrader come ripiego — il sito funziona comunque da subito.

Il prezzo "Cardmarket" mostrato è il prezzo EUR che Scryfall aggiorna ogni
giorno a partire da Cardmarket: è un prezzo di mercato generale, non
filtrato ai soli venditori professionali (quel filtro richiederebbe
l'accesso diretto all'API di Cardmarket, al momento chiuso a nuove
richieste).
