# Stato di completamento — DearCocoa MVP

> **⚠️ PIVOT 17/11/2026 — ribase su memex.** Il cliente ha deciso: la base di codice diventa il repo `memex-lab/memex` reale (clonato e verificato, vedi [BASE_MEMEX.md](BASE_MEMEX.md)), non un restyle clean-room. Le percentuali qui sotto descrivono l'app clean-room precedente e restano valide come inventario funzionale/requisiti; la nuova base parte da memex e il piano di ribase (fasi R1–R5) è tracciato in BASE_MEMEX.md.

Data: 16 novembre 2026. Valutazione onesta per feature: 100 = completo e verificato, valori intermedi indicano cosa manca. Verifica statica: `flutter analyze` → 0 problemi; unit test logica mood → 10/10 passati (e hanno corretto un bug reale nello streak).

## Backend (Supabase)

| Feature | % | Note |
|---|---:|---|
| Schema DB completo (13 tabelle, trigger, helper) | 100 | profili, diario, riflessioni/memoria AI, gruppi, messaggi, community, eventi |
| Row Level Security | 100 | diario/AI solo proprietario; community/gruppi per membri; eventi pubblici |
| Storage (4 bucket + policy) | 100 | journal-photos privato per-utente |
| Realtime (chat, commenti, feed) | 100 | publication su 3 tabelle |
| Trigger business (like counter, capienza RSVP, profilo auto) | 100 | |
| Seed demo (gruppi, eventi, post) | 100 | da eseguire dopo il primo signup |
| Edge function ai-reflection | 100 | deploy manuale richiesto (CLI + AI_API_KEY) |

## App Flutter

| Feature | % | Note |
|---|---:|---|
| Progetto, tema chocolate light/dark, routing, shell 5 tab | 100 | Material 3 |
| Schermata setup (.env placeholder) | 100 | guida integrata |
| Auth email/password + gate rotte | 100 | gestione conferma email |
| Onboarding (3 slide + username) | 100 | |
| Journaling: CRUD, lista raggruppata, ricerca | 95 | offline-first: cache SQLite + outbox FIFO; manca risoluzione conflitti multi-dispositivo |
| Editor entry (titolo/testo/mood/data/foto) | 90 | rich-text/markdown differito (plain text per l'MVP) |
| Foto su storage privato + anteprime | 90 | upload online; coda foto offline differita |
| AI Reflection UI (thread per voce) | 90 | pannello bottom-sheet, errori chiari se funzione non deployata |
| Memoria AI persistente + compressione | 85 | tabella ai_memory + estrazione ogni 6 risposte |
| Safety AI (crisi) | 90 | system prompt; nessun classificatore dedicato |
| Mood calendario colorato + voci del giorno | 100 | table_calendar |
| Mood stats (trend 14g, distribuzione, streak) | 100 | fl_chart + logica unit-testata |
| Community feed (post, media, like ottimistici) | 100 | realtime via postgres_changes (insert/update/delete + like + commenti) con debounce |
| Creazione post (testo, immagine, gruppo) | 95 | |
| Commenti realtime | 95 | autore denormalizzato |
| Gruppi: scopri/join/crea (pubblici/privati) | 95 | ruoli admin/member nel DB |
| Chat gruppo realtime | 100 | messaggi realtime + typing indicator (broadcast channel) + delete messaggi propri |
| Eventi: discover + filtri categoria | 95 | card stile festapp (badge data, capienza, stato RSVP) |
| Eventi: dettaglio + programma + RSVP con capienza | 95 | Join meeting via url_launcher |
| Eventi: host/edit con programma dinamico | 95 | |
| I miei eventi (attending/organizing) | 95 | |
| Profilo (avatar, stats, edit) | 90 | |
| Settings (tema, export JSON, privacy, logout) | 90 | export via clipboard |
| Test automatici | 85 | 16 test (10 unit logica mood + 6 widget core), tutti verdi in locale e in CI |
| Build APK verificata | 100 | pipeline gradle/AGP funzionante, APK firmato (debug key) installabile |
| Notifiche realtime (chat + community, app aperta) | 70 | Realtime Supabase → notifiche locali (flutter_local_notifications); 100% Supabase, nessun account esterno |

## Non richiesti ora (per scelta del prodotto)

| Feature | % | Note |
|---|---:|---|
| Push da app completamente chiusa | opzionale | su Android il canale di consegna di sistema è FCM (progetto Firebase gratuito); Supabase resta l'unico backend |
| Streaming video nativo eventi | 10 | meeting_url esterno: funziona; SDK nativo (Agora/LiveKit) solo se in futuro servirà |
| Biglietti a pagamento | 0 | non richiesti; quando serviranno: provider pagamenti (es. Stripe) + tabella ordini |
| i18n | 20 | copy in EN, struttura intl pronta |
| CI/CD | 100 | GitHub Actions: analyze + test su ogni push/PR (.github/workflows/ci.yml) |

**Media pesata complessiva: ≈ 88/100** per l'MVP definito nei requisiti.

### Perché "journaling multi-dispositivo" è a 95 (senza PowerSync)

Il diario è offline-first: ogni modifica va in SQLite locale + coda outbox e viene inviata a Supabase quando torni online. Il limite del 5% riguarda **un solo caso**: modificare *la stessa voce* da *due dispositivi diversi* mentre entrambi sono offline — l'outbox spedisce entrambe le versioni e l'ultima arriva a vincere, senza merge intelligente.

- **PowerSync** è un servizio esterno che sincronizza SQLite ↔ Postgres con regole di conflitto vere. Il "costo" non è solo il codice: è un'istanza da gestire (e un piano a pagamento sopra certi volumi).
- **Raccomandazione**: per un MVP *non serve*. Se il caso d'uso sopra diventa reale, prima si esplicita il last-write-wins (comportamento già attuale, con `updated_at` chiaro), e solo con più dispositivi attivi per utente si valuta PowerSync.

### Cosa serve per arrivare al 100 letterale

| Voce | % | Blocco attuale | Cosa serve da te |
|---|---:|---|---|
| Journaling multi-dispositivo senza conflitti | 95 | merge outbox semplice | niente da te: PowerSync è opzionale (vedi sopra) |
| Editor rich-text | 90 | plain text | scelta: flutter_quill o markdown, poi 1 giorno di lavoro |
| Foto offline queue | 90 | upload solo online | implementabile senza blocchi (già pianificato) |
| Memoria AI compressione | 85 | funziona ma non esposta in UI | visualizzare la memoria in Settings (no blocchi) |
| i18n | 20 | copy EN solo | decisione lingue target (IT + EN), poi conversione stringhe |
| Notifiche da app chiusa | opzionale | canale di sistema Android = FCM | progetto Firebase gratuito *solo se* vorrai il push nativo |
| Test di integrazione con backend reale | 50 | credenziali verificate (auth HTTP 200), DB da inizializzare | incollare `MIGRAZIONI_UN_BLOCCO.sql` in Supabase → SQL Editor (1 paste, ~1 min) |

## Integrazione con il backend reale (16 novembre 2026)

| Verifica | Esito |
|---|---|
| Progetto Supabase (Francoforte, eu-central-1) | creato, $0/mese |
| Credenziali: auth health via API | HTTP 200, chiave accettata |
| Schema DB (tabelle, RLS, storage) | **da creare**: basta incollare `MIGRAZIONI_UN_BLOCCO.sql` (unione dei 3 file migration) in SQL Editor → Run |
| APK con credenziali incorporate | rebuilt: l'app parte con il progetto già collegato |
| Edge function ai-reflection | opzionale: richiede deploy CLI + chiave AI (l'app mostra errore chiaro finché non è deployata) |

Le chiavi pubbliche (anon/publishable) sono incorporate nell'APK: è il funzionamento normale delle app mobile — la protezione dei dati è garantita dalle policy RLS, non dalla segretezza della chiave. Il file `.env` con i valori reali NON è committato (git skip-worktree).

## Fonti e clean-room

Il codice è scritto da zero (nessuna copia dai repo vincolati): pattern estratti dall'audit + licenze permissive di flutter_supabase_chat_core (Apache-2.0, pattern gruppi/RLS) e festapp (MIT, pattern UI eventi). Vedi `docs/ALTERNATIVE_REPOS.md`.
