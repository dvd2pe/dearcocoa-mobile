# DearCocoa — Gap analysis aggiornata (17/11/2026, post-pivot memex-base)

> Aggiorna [AUDIT_REPOSITORY.md](AUDIT_REPOSITORY.md) (audit statico dei 4 repo) allo
> stato **attuale** dell'app: base memex rinominata `dearcocoa` con fasi R1–R4b
> completate (vedi [BASE_MEMEX.md](BASE_MEMEX.md)). Tutte le verifiche di questa pagina
> sono state rifatte oggi sui cloni dei 4 repo HEAD (pin in [REQUIREMENTS.md](../REQUIREMENTS.md)).

## 1. Verifica dell'audit precedente sul codice reale (17/11/2026)

| Affermazione audit | Esito verifica | Evidenza |
|---|---|---|
| memex = GPL-3.0 | ✅ confermata | `LICENSE` = GNU GPL v3 |
| diaryvault = MIT | ✅ confermata (⚠️ correzione: BASE_MEMEX.md indicava «(GPL-3.0)» — **errato**, corretto in «MIT») | `license.md` = MIT © 2022 Sanketh B.K; GitHub API = MIT |
| instagram clone = MIT + clausola antiriuso-integrale | ✅ confermata | `LICENSE` riga 16: *"in its entirety is not permitted without express written permission from the copyright holder"* (© 2024 Emil Zulufov / ezIT) |
| event-app = MIT, UI-only con dati mock | ✅ confermata | 18 file Dart, `assets/json/data_event.json`, 0 dipendenze di rete/backend nel pubspec |
| memex senza Supabase/cloud sync | ✅ confermata | 0 file in `lib/` citano supabase; local-first drift/filesystem |
| memex senza mood tracking strutturato | ✅ confermata | 31 file citano "mood" ma solo come stringhe prompt/template/skill, nessuna tabella/UI |
| memex: API key LLM in shared_preferences (non secure) | ✅ confermata | pubspec: `shared_preferences ^2.2.2`, assente `flutter_secure_storage` |
| instagram: chat solo 1-1 (gruppo anticipato ma non implementato) | ✅ confermata | `createChat(userId, participantId)` in `chats_repository.dart:57`; colonna `type` esiste in schema PowerSync |
| diaryvault: Firebase solo per auth (niente Firestore/Storage) | ✅ confermata | pubspec: solo `firebase_core` + `firebase_auth` |
| diaryvault: editor rich-text vendored | ✅ confermata | `flutter_quill` via `path: ./packages/flutter_quill` |
| diaryvault: cifratura e2e note | ✅ confermata | `cryptography ^2.9.0` + `lib/features/encryption/` (`encrypted_notes_repository`, `encryption_session_service`) + colonne `enc_` |
| memex: ~221 file di test | ✅ ~confermata | 217 file `*_test.dart` (drift minimo); versione `memex 1.0.39+124` |

**Conclusione**: l'audit precedente è affidabile. Unica correzione fattuale: la licenza diaryvault è **MIT** (iuso 1:1 libero con attribuzione), non GPL.

## 2. Matrice requisiti × stato attuale (dopo R1–R4b sul base memex)

| Req | Come è coperto OGGI | Stato | Gap residuo |
|---|---|---:|---|
| F1 Journaling privato | memex: timeline a card locale (Markdown/filesystem+drift), app-lock biometrico, backup/export `.dearcocoa`, FTS5 | 90% | rich-text editor + tag + reminder granulari (porting diaryvault, MIT) |
| F2 AI reflections | memex: persona chat con memoria persistente (drift + JSONL + compressione), agenti, auto-commento card; backend/ con `RUN_ALL.sql` + edge function dalla prima iterazione | 90% | API key LLM → secure storage; deploy edge function; opt-in esplicito per entry |
| F3 Mood tracking | R4a: tabella drift `MoodEntries` su base memex + UI | 85% | grafici/trend evoluti (fl_chart già nella base), check-in periodico |
| F4 Community spaces | R3b: `CommunityScreen` (Spaces/Groups), feed realtime Supabase, like/commenti | 90% | RLS fine-grained gruppi privati, moderazione, blurhash upload |
| F5 Group conversations | R3c: chat di gruppo realtime (`group_messages`), typing indicator | 90% | allegati in chat, notifica push quando app chiusa |
| F6 Virtual events | R3d: lista/dettaglio/programma/RSVP realtime + seed demo | 85% | streaming video (oggi `meeting_url` esterno), ticket (fuori MVP) |
| F7 iOS + Android | Flutter (base memex, analyze 0 errori; APK Android già verificato in iterazione precedente) | 80% | build iOS di verifica + provisioning (serve macOS/Apple) |
| F8 Secure & scalable | Supabase: RLS, storage policy, realtime publication (RUN_ALL.sql); journal privato resta locale | 85% | audit RLS di perimetro, rate limiting edge, secure keys |

**Media: ≈ 87/100** sui requisiti F1–F8 con il mix attuale (base memex + feature incollate).
Per confronto: i 4 repo usati solo come sorgenti da mixare da zero valgono ~70/100
([AUDIT_REPOSITORY.md](AUDIT_REPOSITORY.md)) — il pivot su memex-base ha chiuso ~17 punti
senza scrivere codice nuovo, proprio perché memex over-delivera (agenti, skills, JS runtime,
STT on-device, OCR, FTS5) e la prima iterazione aveva già lo scheletro Supabase.

## 3. Gap residue, in priorità

**P0 — bloccanti per la demo al cliente**
1. **Build iOS di verifica** (F7): serve ambiente macOS + account Apple; tutto il resto è già cross-platform da Flutter.
2. **Deploy edge function `ai-reflection` + chiave AI** (F2): il codice backend c'è (RUN_ALL.sql + functions), il deploy è manuale (CLI Supabase).
3. **Secure storage per API key LLM** (F2): migrare `shared_preferences` → `flutter_secure_storage` sulla base memex.

**P1 — per il target "quasi production-ready"**
4. **Rich-text editor + tag + export dal diario**: porting diaryvault (flutter_quill vendored, MIT ⇒ si può copiare 1:1 con attribuzione).
5. **Push quando l'app è chiusa**: FCM (Android) + APNs (iOS), inviato da edge functions; le notifiche in-app realtime esistono già (R3).
6. **PowerSync sync-rules lato server**: per l'offline-first completo della social layer (le sync-rules non sono nel repo instagram clone).

**P2 — nice to have / future milestones ($50k budget)**
7. Streaming eventi nativo (Agora/LiveKit) — oggi meeting_url esterno, accettabile per MVP.
8. Ticket a pagamento (Stripe + tabella ordini) — esplicitamente non richiesti ora.
9. i18n (la base memex ha 18 localizzazioni già pronte; diaryvault ne ha 24 come riferimento).
10. Ricerca semantica/embeddings sul diario (memex ha già FTS5+BM25; gli embedding sono un upgrade).

## 4. Licenze — azioni concrete

- **memex (GPL-3.0)**: attribuzione già in `app/THIRD_PARTY_NOTES.md` (R2). L'app derivata deve essere distribuita GPL con sorgenti: **da esplicitare al cliente prima della proposal** (Q2/Q3 del posting). Se il cliente vuole codice chiuso: permesso scritto di memex-lab oppure clean-room dei soli pattern AI.
- **instagram clone (MIT + clausola)**: vietato copiare file interi. Consentito: pattern architetturali e package generici (`env`, `form_fields`, `storage`, `powersync_repository`, auth client). Per il codice integrale serve permesso scritto di itsezlife.
- **diaryvault (MIT) ed event-app (MIT)**: riuso 1:1 consentito con attribuzione in `THIRD_PARTY_NOTES.md`.

## 5. Risposta sintetica alla domanda «quanto matchano?»

- **Da soli, come sorgenti da mixare a mano: ~70/100.** Journaling+AI coperti (diaryvault 74, memex 72), infrastruttura social coperta (instagram 45, ma con clausola licenza), eventi quasi assenti (event-app 25, mock puro).
- **Con il pivot attuale (base memex + R1–R4b): ≈ 87/100** su F1–F8. Manca la coda: iOS build, secure keys, push FCM, rich-text, streaming/ticket — tutte voci P0/P1 con percorso già tracciato.
- Over-delivery dichiarata e benvenuta: memex (sistema agenti, skills, STT, OCR) e instagram clone (PowerSync, stories, OGP) portano qualità oltre l'MVP.
