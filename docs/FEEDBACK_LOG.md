# Feedback log (richieste del cliente)

Tracciamento persistente di tutte le osservazioni / richieste di prodotto.
Fonte: conversazioni 19-20/11/2026. Regola: ogni punto resta aperto finché il
cliente non lo conferma risolto, non solo quando il codice è pronto.

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

---

## Feedback prodotto del 20/11/2026

### F1 — Card di default in timeline: confusione sul click — APERTO (design)
- Sintomo: tutte le card di benvenuto (quote "every record you make",
  "Getting Started", "12 Cross-Record Insight Types", "22 Smart Card Types")
  sono UNA SOLA entry seed (`DemoService._writeIntroCard`) col titolo
  "DearCocoa - Your AI Life Journal" → il tap su una card apre il dettaglio
  del record padre e sembra scollegato.
- Come in Memex: identico (stesse card seed, stesso titolo) — il cliente ha
  confermato di non voler nascondere nulla, quindi le card restano.
- Da decidere (prossima iterazione): rendere il contesto leggibile (sottotitolo
  nel dettaglio / card separate) senza stravolgere Memex.

### F2 — Widget ricreabili dall'utente con il "+" — RISOLTO (v0.3.5)
- Il "+" ora offre il chip **"More types"** con **20 tipi di card creabili a
  mano** nelle 5 categorie Memex (task, event, routine, duration, progress,
  procedure, snippet, article, quote, link, conversation, metric, rating, mood,
  transaction, spec_sheet, person, place, compact, snapshot, gallery).
- Form generico per template (`template_composer.dart` + `template_registry.dart`)
  con campi testo/multiline/numero/stelle/umore/data-foto/ liste/chiave-valore.
- Galleria template: raggiungibile dall'**header timeline** (icona widget) e con
  bottone **"Use this template"** nella preview (prima era debug-only, come in
  Memex; ora va oltre Memex).
- Esclusa su richiesta la parte AI-related (insight_summary e card cross-record
  restano generate dall'agente).
- Nota da Memex originale: lì il "+" apre SEMPRE la chat dell'agente; il composer
  manuale senza AI è un'aggiunta DearCocoa (v0.3.3, estesa in v0.3.5).

### F3 — Community realistica tra utenti — PARZIALE (v0.3.5), resto APERTO
- Fatto in v0.3.5:
  - post con foto (scelta dalla galleria, upload su bucket `post-media`);
  - profilo autore toccabile dal feed (nome, @username, bio, # post, mese di
    iscrizione) — `ProfileSheet`;
  - feed che mostra `media_paths`;
  - seed v3 realistici su Supabase live: 5 avatar profili, post con foto,
    like/commenti incrociati tra i 5 utenti, 3° gruppo "Park Run Buddies"
    con messaggi, evento fisico "Sunrise Park Walk & Coffee" (Villa Borghese,
    Roma) con 4 RSVP.
- Resto aperto (prossime iterazioni, da prioritizzare col cliente):
  1. notifiche (like/commento/risposta) — il loop di ritorno manca ancora;
  2. condividere una card del diario in community (ponte col contenuto);
  3. creazione gruppi da parte utente;
  4. modifica/cancellazione del proprio post.

### F4 — Modifica delle entries in timeline — RISOLTO (v0.3.5)
- Bottone Modifica (matita) nella barra del dettaglio card: apre sheet con
  **titolo, testo, tag** modificabili; salvataggio local-first
  (`safeWriteCardFile` + re-render + `CardUpdatedMessage`) e refresh del dettaglio.
- Restano i gesti nascosti di Memex: long-press ora/luogo, cestino, checkbox.
- L'editing completo via agente AI resta disponibile in parallelo.

### F5 — Event card più ricche — RISOLTO (v0.3.5)
- Card: **immagine di copertina in cima** (`cover_path` + fallback gradiente
  per categoria), **cerchietti partecipanti** (fino a 3 avatar iniziali + "+N",
  con nomi via join client-side), **colori per categoria**
  (wellness=verde, workshop=indaco, community=rosa, meditation=viola,
  social=ambra), riga tempo con **Virtual / luogo**.
- **Eventi fisici**: migration `000005_event_location.sql` (`location` text),
  UI con icona place; il seed crea il primo evento in presenza.
- RSVP: **Join/Going + Maybe(interested)** entrambi funzionanti anche nel
  dettaglio (prima il bottone grande era un no-op che chiudeva la sheet).
- DB live verificato: 4 eventi con cover, 1 fisico, 5 avatar, 3 post con foto.

### F6 — Projects/Areas/Resources/Archives (PARA): come funziona in Memex — RISOLTO (risposta, no codice)
- Verificato sul sorgente originale `memex-lab/memex` (commit base d541b1b5):
  1. le 4 root PARA sono identiche alle nostre (ereditate);
  2. **in Memex sono popolate dall'agente AI**: la skill `manage_pkm`
     ("Organizes user input into P.A.R.A") archivia ogni record nella cartella
     giusta seguendo `pkmPARAStructureExample` (viaggio, ristrutturazione casa,
     patente, ricette…);
  3. la galleria template era debug-only anche in Memex; il "+" in Memex apre
     sempre l'agente.
- Perché "sembrano inutili": senza AI configurata le cartelle restano vuote —
  il valore nasce quando l'AI ci archivia dentro. Con AI on, ogni record finisce
  anche come nota nella Library.
- Decisioni possibili (da scegliere): lasciare così (fedeli a Memex, si riempie
  con AI), oppure aggiungere empty state esplicativi per le 4 root. Nessun
  cambiamento fatto finché il cliente non sceglie.

---

## Infrastruttura (20/11/2026)
- **Repo `dvd2pe/dearcocoa-mobile` reso PUBBLICO** su richiesta: le build
  GitHub Actions su runner standard (ubuntu) ora sono **gratuite e senza
  limite minuti**. Scan segreti prima della pubblicazione: nessun secret nel
  working tree né nella storia (27 commit); solo chiave Supabase publishable
  (pubblica per design) e credenziali demo volute dal cliente.
- v0.3.5 (commit 1d48979 + fix seed baeeb85): analyze 0 errori, **1103 test pass**.
- Migration 000005 + seed v3 **applicati e verificati** sul progetto Supabase live.
- Build split-per-ABI dispatchata → release v0.3.5-dearcocoa con 3 APK.

## Regole di lavoro concordate
- Non chiedere conferme Continue/permessi; lavorare in autonomia.
- Tenere traccia di ogni feedback del cliente in questo file, con stato.
- Prima di chiudere un issue: verifica reale (build/test/screenshot), non solo codice scritto.
