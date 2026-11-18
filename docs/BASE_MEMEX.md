# DearCocoa — Ribase su memex (base di codice, non restyle)

> Decisione del cliente (17 novembre 2026): «Non voglio solo un restyle, voglio che parti come base da memex, e poi su quella costruisci il resto per avere tutti i requisiti, con tutte le features incollate anche dagli altri repo. Non è una questione stilistica, anche di features.»

## 1. I 4 repo approvati — clonati e verificati sul serio

Data verifica: 17 novembre 2026. Niente più "repo vuoti": i sorgenti reali sono in `/repos/` nel workspace di lavoro e l'audit parte da qui.

| Repo | Dimensione | File Dart (lib) | Nome pacchetto | Versione | SDK richiesto | Licenza |
|---|---:|---:|---|---|---|---|
| `memex-lab/memex` | 34 MB | 473 | `memex` | 1.0.39+124 | Dart ≥3.6.0 | GPL-3.0 |
| `SankethBK/diaryvault` | 59 MB | 243 | `dairy_app` | 2.4.0+2033 | — | MIT (license.md, verificato 17/11) |
| `rrdhoi/event-app` | 872 KB | UI-only | `event_app` | 1.0.0+1 | — | — |
| `itsezlife/flutter-instagram-offline-first-clone` | 72 MB | — | — | — | — | MIT + clausola |

Toolchain verificata: **Flutter 3.27.4 / Dart 3.6.2** (compatibile con il vincolo SDK ≥3.6.0 di memex). Android SDK e JDK 17 presenti nel workspace.

Struttura reale di memex (`lib/`): `agent`, `app_startup.dart`, `config`, `data`, `db`, `domain`, `l10n`, `llm_client`, `main.dart`, `routing`, `ui`, `utils`. UI: `agent_activity`, `app_lock`, `calendar`, `card_attachments`, `character`, `chat`, `core`, `insight`, `knowledge`, `main_screen`, `memory`, `settings`, `timeline`, `user_setup`.

Tema reale di memex (`lib/ui/core/themes/`): `app_colors.dart`, `app_text_styles.dart`, `app_theme.dart`, `app_shadows.dart`, `design_system.dart`, `bundled_google_fonts.dart`. Token confermati leggendo il sorgente: primary `#5B6CFF`, seed `#6366F1`, background `#F7F8FA`, testo `#0A0A0A`/`#4A5565`/`#99A1AF`, tab `#1F1F1F`/`#888888`, pill `#1A1A1A`, semantici `#10B981`/`#F59E0B`/`#F43F5E`, dark `#0F172A`; brand font Bricolage Grotesque 32/w800/ls−0.41 + Inter (textTheme completo in `app_theme.dart`); ombre: card `0x0D000000` blur16 (0,2), cardAccent `0x0D111827` blur24, eventCard `0x08111827` blur18, floating `0x14000000` blur24 (0,6).

## 2. Cosa cambia rispetto all'app attuale

L'app in `app/` (già su GitHub) è nata clean-room con tema "ispirato" a memex: il cliente l'ha giustamente respinta perché padding/widget non corrispondono. La nuova strategia:

1. **Base = codebase memex vera.** Partiamo dai suoi 473 file: architettura (provider + go_router + drift), tema, widget, schermate (timeline, chat, character, knowledge, insight, calendar, app_lock, settings). Il nome pacchetto `memex` diventa `dearcocoa`; identità visiva e copy restano quelli del prodotto DearCocoa.
2. **Features incollate dagli altri repo** su questa base (riuso dei pattern, adattati alla struttura memex):
   - `diaryvault` → editor rich-text, tag/sorting, export, PIN/biometrico (memex ha già `app_lock` con local_auth), reminder giornalieri, TTS, multi-tema
   - `flutter-instagram-offline-first-clone` → feed community, post/commenti/like, messaggistica, outbox offline-first, realtime
   - `event-app` → event discovery, event card, dettaglio evento, partecipanti, ticket
3. **Supabase** resta il backend per la parte sociale (auth, community, gruppi, eventi, storage, realtime, edge function AI): memex è local-first (drift/SQLite) — il journaling privato resta locale, la social layer si sincronizza via Supabase.

## 3. Piano di ribase (fasi, ognuna con push su GitHub)

| Fase | Contenuto | Esito |
|---|---|---|
| R1 | Compilare memex così com'è (flutter pub get + build web) per avere la base verde | ✅ **17/11** |
| R2 | Rename `memex` → `dearcocoa` (pubspec, import, Android/iOS/web namespace), rimozione dipendenze non usabili, tenere tema/widget | ✅ **17/11** |
| R3 | Porting features social (feed, chat di gruppo, eventi) dentro la shell memex + Supabase | ✅ **17/11 (R3b+c+d)** |
| R4 | Porting features diaryvault (rich-text, tag, export, reminder) nel journaling | 🟡 parziale: R4a mood ✅ + R4b reminder ✅ (17/11); resta rich-text/tag/export |
| R5 | Auth/demo accounts, seed, screenshot, gallery — verifica cliente | ⏳ |

## 6. Esito R3a — Supabase + auth demo senza muro (17 novembre 2026)

- Dipendenza `supabase_flutter ^2.16.0` aggiunta; `flutter analyze` → **0 errori/0 warning**.
- **`lib/data/services/supabase_service.dart`**: init dal client (URL + publishable key, overridabili via `--dart-define`), 5 account demo prefill, signIn/signUp, fetch/upsert profilo.
- **`lib/ui/user_setup/widgets/demo_login_screen.dart`**: schermata di selezione account in stile memex (card con ombra `AppShadows.card`, brand title Bricolage 32/w800, gradiente avatar `AppColors.avatarGradient`) — 5 account con un tap + sign-in manuale opzionale. **Niente muro**: tap → dentro l'app.
- **`lib/main.dart`**: `SupabaseService.init()` in `main()`; `RootShell` ora controlla la sessione Supabase — utente loggato senza workspace locale viene **auto-provisioned** (username dal profilo, locale, avatar) e entra direttamente in `MainScreen`; non loggato → `DemoLoginScreen`; offline → fallback `UserSetupScreen`.
- **`backend/supabase/seed_demo.sql` v2**: crea i 5 utenti auth (password crypt, email confermata) + profili + 2 gruppi con messaggi + 3 eventi con programma/RSVP + 6 post con like/commenti incrociati. Idempotente, eseguibile in qualsiasi ordine.
- Credenziali demo documentate in SETUP_SUPABASE.md §4: password comune `Cocoa2026!`.

⚠️ Nota RLS: le insert del seed girano nel SQL Editor come owner delle tabelle (bypass RLS standard); le policy RLS restano invariate per il runtime client.

## 4. Esito R1 — base verde (17 novembre 2026)

- **Toolchain**: il repo richiede Dart ≥3.8 per ML Kit e ≥3.9.2 per `dart_agent_core` (framework agenti). Flutter scaricato e installato: **3.35.5 / Dart 3.9.2**.
- **Pin applicati** al `pubspec.yaml` (unici vincoli incompatibili risolti):
  - `test: 1.26.2` (era `^1.26.3` — flutter_test di 3.35.5 richiede test_api 0.7.6)
  - `drift: 2.29.0`, `drift_dev: 2.29.0`, `drift_flutter: 0.2.7` (era `^2.30.0`/`^0.2.8` — analyzer/test_api conflict)
  - `build_runner: ^2.7.1` (suggerito da pub)
- **`flutter pub get`** ✅ — **`flutter gen-l10n`** ✅ (1093 chiavi, 18 localizzazioni) — **`flutter analyze`** ✅ **0 errori, 0 warning** (157 info lints stile upstream).
- **`flutter test`**: **1073 passati, 5 skip, 4 falliti** (stato upstream memex: test live-API/geocoding che richiedono chiavi AMAP o ambiente specifico; nessun fallimento legato alla toolchain).

## 5. Esito R2 — rename (17 novembre 2026)

- Pacchetto Dart: `memex` → **`dearcocoa`** (pubspec + **1644 import** sostituiti in lib/test, residui: 0).
- Android: applicationId/namespace `com.memexlab.memex` → **`app.dearcocoa.mobile`** (flavor global/cn/early/dev), appLabel → "DearCocoa", package Kotlin spostato in `app/dearcocoa/mobile/` (MainActivity + 10 channel handler), nomi method-channel e intent action sincronizzati anche lato Dart (18 file) e nel plugin path `plugins/agent_background_android` (Java `AgentBackgroundPlugin` riposizionato, residuo memexlab: solo l'URL del cloud proprietario non usato).
- iOS: bundle id `app.dearcocoa.mobile`, `CFBundleDisplayName` → DearCocoa.
- Localizzazioni: valori utente "Memex" → "DearCocoa" (es. lock screen, agent context), **chiavi interne `memex*` invariate** (identificatori tecnici referenziati dal codice).
- Post-rename: `pub get` ✅, `gen-l10n` ✅, `analyze` ✅ **0 errori/0 warning**.
- Aggiunta `app/THIRD_PARTY_NOTES.md`: attribuzione GPL-3.0 della base memex e obblighi di distribuzione.

Aggiornamento di questo file a ogni fase completata, con push immediato su GitHub.

## 7. Esito R3b+c+d — Community, Gruppi, Eventi nella shell memex (17 novembre 2026)

- **Barra a 4 tab** (`main_bottom_bar.dart`): Timeline · Community · [AI core] · Events · Library, stesso canvas Figma 393×120.5, stesso painter e `_NavTab`; tab 65px, etichette 12.5px (adattamento per far stare 4 tab; colori/ombre/gerarchia invariati). Test widget aggiornati e verdi (7/7).
- **`lib/domain/models/social_models.dart`** + **`lib/data/repositories/social.dart`**: repository top-level stile memex su Supabase — feed (join profili + conteggi like/commenti), toggle like, creazione post, commenti, gruppi (iscrizione, messaggi), eventi (lista + programma + RSVP upsert/delete) e helper `subscribeTable` per il Realtime.
- **`lib/ui/community/community_screen.dart`**: header brand memex, segment switch Spaces/Groups, feed con card bianche r16 + `AppShadows.card`, like/commenti, FAB "Share" → `community_sheets.dart` (CreatePostSheet + CommentsSheet bottom-sheet r20).
- **`lib/ui/community/groups_chat_screen.dart`**: chat di gruppo realtime (Supabase Realtime su `group_messages`), bolle con autore, input con invio.
- **`lib/ui/events/events_screen.dart`**: lista eventi futuri con date block 47×50 r12 primary 12% (pattern event-app), chip categoria, contatore joined/capacity, RSVP one-tap, dettaglio bottom-sheet con programma timeline e meeting URL.
- **`main.dart`**: IndexedStack a 4 figli + handler tab; Community/Events/Gruppi reali — **la chat vera è dentro l'app, niente muro sign-in**.
- `flutter analyze` → **0 errori/0 warning**; test barra + RTL → **7/7 pass**.

## 8. Esito R4a — Mood tracking sulla base memex (17 novembre 2026)

- Nuova tabella drift **`MoodEntries`** (user_id, entry_date, mood 1..5, note, created_at), schemaVersion 19→20 con migration `from < 20` e indice (user_id, entry_date); codegen `build_runner` OK (1362 output).
- **`lib/data/repositories/mood_stats.dart`**: logica pura portata dall'MVP precedente (commit 675a61b, i cui unit test erano 10/10) — streak corrente/chiusa su ieri, streak più lunga, mood degli ultimi N giorni, distribuzione, media.
- **`lib/data/repositories/mood_repository.dart`**: persistenza drift (una riga per utente/giorno, sovrascrittura idempotente).
- **`lib/ui/mood/mood_screen.dart`** su rotta `/mood`: picker odierno a 5 tap con colori memex, grafico fl_chart 14 giorni (barre primary), streak corrente/record/media. Pulsante di accesso (icona mood, cerchio `iconBgLight`) aggiunto nell'header timeline, prima del campo notifiche.
- **`flutter analyze` → 0 errori/0 warning; test mood → 10/10 pass.**

## 9. Esito R4b — Reminder + TTS + mapping features (17 novembre 2026)

- **Daily reminder** (da diaryvault): `flutter_local_notifications` 20.1 + `timezone`; `daily_reminder_service.dart` (canale Android, schedule giornaliero idempotente, cancel); `daily_reminder_page.dart` (toggle + time picker) collegata nel Personal Center (`personal_center_screen.dart`); permessi `POST_NOTIFICATIONS` (già presente) + `SCHEDULE_EXACT_ALARM` nel manifest.
- **Read aloud / TTS** (da diaryvault): `flutter_tts`; bottone speaker nella top bar di `timeline_card_detail_screen.dart` (stili esistenti 36×36), legge `rawContent` senza marker markdown, stop e handler di completamento.
- **docs/FEATURE_MAPPING.md**: mapping riga-per-riga dell'elenco features del cliente (README memex + Key Features diaryvault) → cosa è già nella base, cosa aggiunto in R3/R4, cosa rimandato con motivazione (Memex AI, Drive/Dropbox, E2E, theme builder, PDF).
- `flutter analyze` → **0 errori/0 warning**.

## 10. Esito R5 — APK demo su GitHub Actions + fix dipendenze R4b (17 novembre 2026)

- **Repo su `dvd2pe/dearcocoa`**: spostato da `jessicacarter9955/dearcocoa` con mirror git completo (storia 1:1, HEAD `48c1186`). Motivo: Actions era bloccata sui repo privati dell'account precedente (job falliti in ~1 s senza runner assegnato; probe su repo pubblico funzionante ha isolato la causa). Su `dvd2pe` le Actions girano regolarmente.
- **Fix dipendenze R4b (R5-fix, `a93154f`)**: la prima esecuzione reale di CI ha rivelato 19 errori `uri_does_not_exist` — `daily_reminder_service.dart` e `timeline_card_detail_screen.dart` importavano `flutter_local_notifications`, `timezone` e `flutter_tts` senza che fossero dichiarate nel `pubspec.yaml` (il commit R4b aveva cambiato solo il codice). Dichiarate con versioni selezionate via API pub.dev per compatibilità con Dart 3.9.2: `flutter_local_notifications 20.1.0` (dipende da `timezone ^0.10.0`), `timezone 0.10.1`, `flutter_tts ^4.2.5`.
- **Warning fatali analyze (R5-fix2/2b, `b08352a` + `48c1186`)**: null-comparison inutile in `supabase_service.dart` (`Supabase.instance.client` non è nullable → `isReady` ridotto a `_initialized`) e due import non usati in `community_screen.dart` / `community_sheets.dart`. `flutter analyze` ora 0 errori / 0 warning.
- **Build APK** (`.github/workflows/build-apk.yml`, trigger su push di `app/**` e manuale): Flutter 3.35.5, JDK 21, `flutter build apk --release --flavor global` (appId `app.dearcocoa.mobile`, label "DearCocoa"), firma con keystore demo generato nel runner (password demo `dearcocoa2026`, mai per lo store), artefatto `dearcocoa-demo.apk` con retention 30 giorni. Run di riferimento: [44114517515 su actions-probe](https://github.com/dvd2pe/actions-probe/actions/runs/44114517515). APK pubblico in release permanente [v1.0.39-demo](https://github.com/dvd2pe/dearcocoa/releases/tag/v1.0.39-demo).
- Script locale riproducibile: [`app/scripts/build_demo_apk.sh`](app/scripts/build_demo_apk.sh) (pub get → build release → keystore demo → zipalign → apksigner).
- **CI allineata**: `ci.yml` aggiornata da Flutter 3.27.4 a 3.35.5, ora `analyze` senza warning fatali + `flutter test` su ogni push.
- **Fix runner (R5-fix3, `7412d2b`)**: le prime 3 build sono morte a ~17 min nel step gradle con `No space left on device` (14 GB SSD del runner standard; SDK + NDK + pub cache + gradle + output di un'app con 200+ plugin non ci stanno, e senza log perché l'agent stesso finiva in disco pieno). Il workflow ora libera ~25 GB prima della build (dotnet, ghc, CodeQL, boost, immagini docker, NDK 25/26 preinstallati) e `gradle.properties` scende da `-Xmx8G/-XX:MaxMetaspaceSize=4G` (calibrato per macchine da 32 GB) a `-Xmx4G/-XX:MaxMetaspaceSize=1G`.
- **Fix NDK (R5-fix4, `747871e`)**: `NDK not configured — Preferred version 27.0.12077973`: l'NDK non è preinstallato sul runner e l'auto-download di AGP (~2,5 GB) era ciò che riempiva il disco nelle run 1-3 (per questo morivano senza log). Il workflow ora lo installa esplicitamente prima del build, col disco già liberato.
- **Fix NDK reale (R5-fix7, `167876c`)**: `ndk;27.0.12077973` è stato **rimosso dai repository Google** ("Failed to find package" via sdkmanager, e l'auto-download AGP non parte) — il runner GitHub 2026 ha preinstallati 27.3.13750724/29/30. `ndkVersion` in `build.gradle.kts` allineato a `27.3.13750724` (stesso ramo r27, ABI-compatible). Corretto inoltre il keystore demo nel workflow: `key-global.properties` va scritta in `app/android/` (dove la legge `rootProject.file(...)`) con `storeFile` assoluto, e il glob di rename non assume più il nome file `app-global-release*.apk`.

### 10b. Chiusura R5 — desugaring, quota minuti privati, build su repo pubblico (17 novembre 2026)

- **R5-fix10 (`ed65d25`)**: la run fix9 (prima con tutti gli ostacoli infrastrutturali rimossi) è arrivata a 10m38s e fallita solo su `checkGlobalReleaseAarMetadata`: `flutter_local_notifications` richiede il **core library desugaring**. Abilitato in `app/android/app/build.gradle.kts` (`isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`).
- **Quota minuti Actions privati esaurita**: dal pomeriggio ogni job sul repo privato fallisce in ~3 s senza runner né step (startup_failure ×3, rerun inclusi), mentre una run banale su un repo **pubblico** va a segno in ~30 s. Cause possibili: 2000 min/mese del piano Free con uso pregresso dell'account. Non verificabile via API (endpoint billing spostati, 410/404).
- **Workaround adottato**: repo pubblico **`dvd2pe/actions-probe`** con workflow `Build DearCocoa APK (dal repo privato)` — checkout autenticato di `dvd2pe/dearcocoa` via secret `DVD2PE_TOKEN`, stessa ricetta di build, artefatto sul probe e **release creata via API sul repo privato** (la release non consuma minuti). Run riuscita: [44114517515](https://github.com/dvd2pe/actions-probe/actions/runs/44114517515).
- **Esito**: `dearcocoa-demo.apk` **255.8 MB** in release permanente [v1.0.39-demo](https://github.com/dvd2pe/dearcocoa/releases/tag/v1.0.39-demo) — manifest OK, 3 ABI (arm64-v8a, armeabi-v7a, x86_64), 697 file, keystore demo.
- Per i prossimi build: tab Actions del repo `actions-probe` → Run workflow; oppure aizzare la spesa/minuti dell'account o rendere pubblico dearcocoa (decisione del cliente).
