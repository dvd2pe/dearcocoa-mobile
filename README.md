# DearCocoa 🍫

Social wellness platform per iOS e Android: journaling AI local-first (frammenti testo/foto/voce organizzati in timeline cards), riflessioni AI, mood tracking, spazi community, conversazioni di gruppo ed eventi virtuali.

**Base di codice:** [`memex-lab/memex`](https://github.com/memex-lab/memex) (GPL-3.0, commit `d541b1b5`) rinominato `dearcocoa` ed esteso con le feature social. Attribuzione e note di terze parti: [THIRD_PARTY_NOTES.md](THIRD_PARTY_NOTES.md).

**Stack:** Flutter 3.35.5 · Supabase (auth, Postgres+RLS, Storage, Realtime, Edge Functions) · LLM multi-provider BYO (17 provider: OpenAI, Claude, Gemini, DeepSeek, Ollama…) · drift/SQLite (local-first).

## Stato

| Fase | Esito |
|---|---|
| R1 base memex compilata | ✅ analyze 0 errori, 1073 test pass |
| R2 rename memex → dearcocoa | ✅ 1644 import, `app.dearcocoa.mobile`, iOS, canali |
| R3 Supabase + community/gruppi/eventi realtime | ✅ feed, chat di gruppo, eventi RSVP, barra 4 tab |
| R4 mood tracking + daily reminder + TTS | ✅ drift v20, test mood 10/10 |
| R5 build APK release firmato | ✅ 255.8 MB (demo keystore) |
| M12.1 questo repo pubblico (CI + build Actions native) | 🔄 in corso |

## Account demo (prefill nella login, sign-in con un tap)

| Account | Email | Password |
|---|---|---|
| Sofia Rossi | `sofia@dearcocoa.demo` | `Cocoa2026!` |
| Luca Bianchi | `luca@dearcocoa.demo` | `Cocoa2026!` |
| Giulia Ferrari | `giulia@dearcocoa.demo` | `Cocoa2026!` |
| Marco Conti | `marco@dearcocoa.demo` | `Cocoa2026!` |
| Elena Moretti | `elena@dearcocoa.demo` | `Cocoa2026!` |

Il seed [`backend/supabase/seed_demo.sql`](backend/supabase/seed_demo.sql) crea anche gli utenti auth: eseguilo nell'SQL Editor (idempotente). Setup completo: [docs/SETUP_SUPABASE.md](docs/SETUP_SUPABASE.md).

## Build APK (sempre `--release`)

**GitHub Actions (consigliato):** push su `main` (paths `app/**`) o **Run workflow** su `Build APK release` → artefatto `dearcocoa-release-apk`. Se i secrets `KEYSTORE_BASE64`/`STORE_PASSWORD`/`KEY_PASSWORD`/`KEY_ALIAS` sono settati usa il keystore release, altrimenti genera un keystore demo (solo test, mai store).

**Locale:** `bash app/scripts/build_demo_apk.sh`

Toolchain: Flutter 3.35.5 · JDK 21 · AGP 8.11.1 · NDK 27.3.13750724 (allineato nel gradle; il 27.0.12077973 non è più scaricabile) · CMake 3.22.1 (tarball Kitware: sherpa_onnx compila C++ nativo).

Nota APK: ~255 MB (fat) per i modelli speech nativi sherpa_onnx — backlog: split-per-abi + pruning modelli.

## Struttura

- [`app/`](app/) — app Flutter (base memex → dearcocoa, licenza GPL-3.0 ereditata)
- [`backend/supabase/`](backend/supabase/) — migration SQL (13 tabelle + RLS + storage + realtime), seed demo, edge function `ai-reflection` (`RUN_ALL.sql` esegue tutto in ordine)
- [`docs/`](docs/) — BASE_MEMEX (piano ribase R1-R5), SETUP_SUPABASE, FEATURE_MAPPING, GAP_ANALYSIS, STATO_COMPLETAMENTO

## CI

- `ci.yml` — `flutter analyze` + `flutter test` su push/PR (Flutter 3.35.5)
- `build-apk.yml` — build APK release firmato su push `app/**` o dispatch

## Licenza

GPL-3.0 ereditata dalla base memex: vedi [LICENSE](LICENSE) e [THIRD_PARTY_NOTES.md](THIRD_PARTY_NOTES.md).
