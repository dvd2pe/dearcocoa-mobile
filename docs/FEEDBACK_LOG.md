# Feedback log (richieste del cliente)

Tracciamento persistente di tutte le osservazioni / richieste di prodotto.
Fonte: messaggio del 20/11/2026 + conversazioni precedenti. Regola: ogni punto
resta aperto finché il cliente non lo conferma risolto, non solo quando il codice è pronto.

Stato: `APERTO` = da fare · `IN ANALISI` = decisione di design da prendere · `RISOLTO` = fatto e verificato

---

## Lista issue (colonna sonora)

### #7 — Errore caricamento Community / Eventi / Gruppi — RISOLTO (v0.3.4)
- Causa radice confermata: **PGRST200**. Gli embed PostgREST `profiles!..._fkey`
  puntavano a FK verso `auth.users`, che PostgREST non può esporre → la query
  feed/eventi/gruppi falliva sempre.
- Fix v0.3.4: migration `000004_social_profiles_fks.sql` (FK ri-puntate a
  `public.profiles`) + join profili lato client (`fetchProfileNames` in
  `social.dart`) + mapper puri testati. Verificato via REST (query app = 200).
- Contesto: era già presente il pulsante "Diagnostica" accanto a Retry (v0.3.3).

---

## Feedback prodotto del 20/11/2026

### F1 — Card di default in timeline: cosa sono e confusione sul click — IN ANALISI
- Sintomi osservati dal cliente: card "every record you make" (quote),
  card "Getting Started" con task, "12 cross record", ecc.
- **Bug/confusione confermata nel codice**: tutte quelle card sono UNA SOLA
  entry di benvenuto scritta da `DemoService._writeIntroCard()` (6 uiConfigs:
  snapshot, snippet, metric "22 Smart Card Types", rating "12 Cross-Record
  Insight Types", task "Getting Started", quote slogan) attaccate a UN record
  il cui titolo è `introTitle` = **"DearCocoa - Your AI Life Journal"**.
  Quindi quando si tocca la task card si apre il dettaglio del record con quel
  titolo: da qui la domanda del cliente "che c'entra con la todo card?".
- Decisione da prendere: intro card più leggibili (una card = un record),
  titolo di contesto, o tutorial esplicativo.

### F2 — Widget/card ricreabili dall'utente con il "+" — APERTO
- Motore rendering: **22 template in 5 categorie** (NativeCardFactory):
  Productivity: task · routine · event · duration · progress
  Knowledge: article · snippet · quote · link · conversation · procedure
  Data: metric · rating · transaction · spec_sheet
  People & Places: person · place · mood · compact
  Visual: snapshot · gallery · video
- Percorso di creazione attuale:
  - "+" con AI configurata → chat Super Agent (può creare qualsiasi template).
  - "+" SENZA AI → `SimpleNoteComposer` con soli **3 tipi**: Nota (snippet),
    Task, Rating.
  - Galleria template (`TimelineTemplateGalleryPage`) è **solo showcase e
    raggiungibile solo da pagina debug** (Debug settings), non creabile.
- Richiesta: rendere gli altri template creabili dall'utente (template picker
  nel "+" o galleria con "usa questo template").

### F3 — Community: cosa ci fa davvero l'utente? — APERTO (design loop)
- Azioni esistenti (v0.3.4): leggere post dei 5 utenti demo, Like, Commento,
  pubblicare post di **solo testo**, entrare/uscire dai gruppi, chat di gruppo
  realtime. Realtime attivo su space_posts e group_messages.
- Mancanze identificate (da decidere il taglio):
  1. nessun ponte col contenuto personale: non si può condividere in community
     una card/record del proprio diario (il cuore dell'app);
  2. niente profili (tap su autore, lista membri, follow);
  3. niente notifiche (like/commento/risposta non avvisano nessuno);
  4. post senza immagini, niente modifica/cancellazione del proprio post;
  5. gruppi: solo 5 gruppi seed, nessuna creazione gruppo da parte utente;
  6. niente aggancio event↔group↔post.
- Richiesta cliente: ragionare come product designer sui loop d'uso, non
  lasciare la community come "lettura del DB".

### F4 — Modifica delle entries in timeline — APERTO (confermato il gap)
- Stato attuale: **non esiste modifica di titolo/testo/tag** dell'entry.
- Esiste invece (nascosto): long-press sull'ora → cambia data/ora;
  long-press sulla località → cambia luogo; cestino → cancella;
  checkbox dei task card toggle in-place; barra in basso = solo commento.
- Modifica completa del contenuto solo via AI agent (tool update per fact_id),
  quindi richiede AI configurata.
- Richiesta cliente: editing manuale delle entries.

### F5 — Event card più ricche — APERTO
- Richiesta: card dettagliate e colorate, immagine in cima, piccoli cerchi con
  i partecipanti (avatar), supporto a eventi **non solo virtuali**.
- Stato backend (già pronto, UI non lo usa):
  - `events.cover_path` esiste + bucket storage `event-covers` (lettura
    pubblica) — la UI non mostra alcuna cover;
  - `events.is_virtual` esiste (default true) — la UI scrive hardcoded
    "· virtual"; manca però una colonna `location`/venue per eventi fisici;
  - RSVP: status going/interested/cancelled (la UI usa solo going/cancelled;
    niente avatar partecipanti, solo numero);
  - il bottone grande "Join this event" nel dettaglio è un **no-op** (fa solo
    pop della sheet);
  - nessuna creazione evento da parte utente (solo seed).
- Categoria enum attuale: wellness / workshop / community / meditation / social.

### F6 — Projects / Areas / Resources / Archives: a cosa servono — IN ANALISI
- È il metodo **PARA** (Tiago Forte), replicato dall'app Memex originale:
  - Projects = note legate a risultati attivi con scadenza (vita breve);
  - Areas = responsabilità continue della vita (salute, finanze, casa);
  - Resources = materiale di riferimento per temi/interessi (non azionabile);
  - Archives = ciò che dei tre sopra non è più attivo (solo consultazione).
- Perché "sembrano tutte identiche": le pagine interno-cartella usano le stesse
  card bianche per ogni root; le differenze (colori indigo/emerald/amber/slate
  e sottotitoli) esistono solo nella griglia iniziale. Contenuti seed quasi
  nulli (solo DearCocoa Guide.md in Resources).
- Esiste già CRUD utente senza AI: + (nuova cartella/nota), long-press →
  sposta verso altra root PARA / elimina.
- Da decidere: differenziare le 4 root (empty state esplicativi, comportamento
  AI per archiviazione automatica, badge "attivo/scaduto" per Projects).

---

## Regole di lavoro concordate
- Non chiedere conferme Continue/permessi; lavorare in autonomia.
- Tenere traccia di ogni feedback del cliente in questo file, con stato.
- Prima di chiudere un issue: verifica reale (build/test/screenshot), non solo codice scritto.
