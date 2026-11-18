# Mapping features — elenco del cliente ↔ base DearCocoa

Risposta onesta alla domanda «Poi abbiamo implementato questi?» (17/11/2026). Con il pivot **memex come base di codice**, la maggior parte delle feature dell'elenco memex **è già nel prodotto perché è nel codice della base**, non va re-implementata. Questo file dice riga per riga dove stanno (file reali della base), cosa è stato aggiunto sopra la base e cosa è rimandato, con motivazione.

## 1. Da memex (README del repo)

### 🤝 AI Companion
| Feature richieste | Stato | Dove (file reali nella base) |
|---|---|---|
| AI characters con personalità | ✅ nella base | `lib/ui/character/`, `lib/data/services/character_service.dart` (file YAML per character, `CharacterModel`) |
| Auto-commento sulle nuove card | ✅ nella base | `lib/agent/comment_agent/comment_agent.dart` + `lib/data/repositories/post_comment.dart` (CommentAgent.runWithContent) |
| Chat 1v1 con memoria di contesto | ✅ nella base | `lib/ui/character/widgets/persona_chat_screen.dart` + drift `PersonaChatMessages` + PKM context |
| Memoria persistente tra scene | ✅ nella base | `lib/agent/memory/` + compressione memoria + `lib/ui/memory/` |
| SillyTavern import (V2 JSON+PNG) | ✅ nella base | `lib/ui/character/widgets/tavern_import_screen.dart` |

### 📝 Pure Text & Data Freedom
| Feature | Stato | Dove |
|---|---|---|
| Records come Markdown files | ✅ nella base | il timeline/journal di memex salva card come file Markdown sul filesystem (`CardCache` + FileSystemService) |
| Export/zero vendor lock-in | ✅ nella base | backup completo + export Markdown (BackupService) |

### 🔒 Privacy & Local-First
| Feature | Stato | Dove |
|---|---|---|
| Dati locali (filesystem + SQLite) | ✅ nella base | drift `AppDatabase` (schema v20) + workspace locale |
| App lock biometrico | ✅ nella base | `lib/ui/app_lock/` con `local_auth` (il README del cliente elencava "PIN, fingerprint" — c'è) |
| No cloud dependency per il diario | ✅ nella base | il journal resta locale; solo la social layer usa Supabase |

### 📂 Storage & Backup
| Feature | Stato | Dove |
|---|---|---|
| iCloud Drive / cartella custom / app storage | ✅ nella base | `DataStoragePage` + `StorageLocation` (icloud/custom/app) |
| One-tap backup / restore | ✅ nella base | `lib/data/services/backup_service.dart` + `backup_restore_page.dart` |

### 🔗 Multi-LLM Provider
| Feature | Stato | Dove |
|---|---|---|
| 17 provider (Gemini OAuth, OpenAI/Claude/Gemini, Bedrock, Kimi, Qwen, GLM, DeepSeek, MiniMax, MIMO, OpenRouter, Ollama…) | ✅ nella base | `lib/domain/models/llm_config.dart` (LLMConfig, ~17 tipi) + `lib/llm_client/` + `dart_agent_core`; config per agente (`getAgentLLMResources`) |
| Memex AI (servizio gestito) | ⛔ n/a | servizio cloud proprietario di memex-lab: non attivabile per DearCocoa (non abbiamo l'account/servizio) — i 16 altri provider restano disponibili |
| OAuth Google/OpenAI "unofficial" | ✅ nella base | `lib/llm_client/gemini_oauth_client.dart`, CodexResponsesClient |
| Location context opzionale (GPS + reverse geocoding, OSM/Amap) | ✅ nella base | geolocator + `lib/data/services/geocoding_service.dart` + toggle in Settings |

### 🧩 Custom Agent System
| Feature | Stato | Dove |
|---|---|---|
| Creazione agenti liberi (Pure mode) | ✅ nella base | `lib/ui/agent_activity/` + `custom_agent_config_page.dart` |
| Trigger event-driven (nuova card, commento, cambio UI, dati locali) | ✅ nella base | EventBusService + task_handlers |
| LLM per-agente | ✅ nella base | UserStorage.getAgentLLMResources |
| System prompt custom | ✅ nella base | agent config |
| Skills standard (SKILL.md) + working directory + JS con fetch() | ✅ nella base | `lib/agent/skills/` (8 skill built-in) + `flutter_js` runtime |
| Catene di dipendenza tra agenti (dependsOn) | ✅ nella base | dart_agent_core AgentController |
| Sync/async + retry configurabile | ✅ nella base | run_mode + LocalTaskExecutor (workmanager) |

## 2. Da diaryvault (Key Features)

| Feature richieste | Stato | Dove |
|---|---|---|
| Rich text editor con immagini/video/audio | ✅ nella base | card editor memex con allegati media (image_picker, record, wechat_assets_picker, video_player+chewie, `card_attachments/`) |
| Cloud backup (Drive/Dropbox/Nextcloud) | ⚠️ parziale | la base ha iCloud/cartella custom/app storage + backup one-tap (§1). Drive/Dropbox/Nextcloud espliciti rimandati (fase R5+ su richiesta) — Supabase Storage è già il cloud della social layer |
| Sync multi-device | ⚠️ parziale | social layer realtime via Supabase; journal multi-device via backup/restore + export (live-sync del journal rimandato) |
| Tag e sorting (recent/old/A–Z) | ✅ nella base | tag chips + filtri timeline memex |
| Export text/PDF | ✅ parziale | export Markdown/file; PDF via stampa sistema rimandato |
| PIN + fingerprint + E2E encryption | ✅ nella base (PIN/biometrico via `app_lock`); ⛔ E2E note encryption rimandata (memex non la implementa; fase successiva) |
| Daily reminder notifications | ✅ **aggiunto (R4b)** | `lib/data/services/daily_reminder_service.dart` + `daily_reminder_page.dart` (flutter_local_notifications, canale DearCocoa, permesso Android 13+) |
| Auto-save | ✅ nella base | autosave editor card |
| Temi multipli + theme builder | ⚠️ parziale | light/dark (AppTheme.lightTheme/darkTheme); theme builder custom rimandato |
| Font customization per app/per nota | ⛔ rimandato | la base usa Bricolage Grotesque + Inter (vincolo del cliente: memex è la fonte visiva) |
| 24 lingue | ⚠️ parziale | la base ha 18 localizzazioni memex (l10n) |
| Read aloud (TTS) | ✅ **aggiunto (R4b)** | bottone speaker in `timeline_card_detail_screen.dart` (flutter_tts, strip markdown, stop/riprendi) |
| Mood tracking | ✅ **aggiunto (R4a)** | `mood_stats.dart` + `mood_repository.dart` (drift `MoodEntries` v20) + `/mood` screen (picker, chart fl_chart 14 giorni, streak) |

## 3. Feature DearCocoa specifiche (fuori dai README, dai 6 requisiti del job)

| Feature | Stato | Dove |
|---|---|---|
| Community spaces (feed, post, like, commenti) | ✅ R3c | `lib/ui/community/community_screen.dart` + `social.dart` (Supabase + Realtime) |
| Group conversations real-time | ✅ R3c | `lib/ui/community/groups_chat_screen.dart` |
| Virtual events (lista, dettaglio, programma, RSVP) | ✅ R3d | `lib/ui/events/events_screen.dart` + pattern event-app |
| 5 demo account one-tap + seed | ✅ R3a | `supabase_service.dart` + `demo_login_screen.dart` + `seed_demo.sql` v2 |

## 4. Cosa resta fuori (onesto)

1. **Memex AI** (servizio gestito del vendor) — non attivabile.
2. **Drive/Dropbox/Nextcloud espliciti** per il backup diario — sostituiti da iCloud/cartella/app + Supabase per la social.
3. **E2E note encryption** e **theme builder/font customization** — rimandati; contraddirebbero comunque il vincolo "tema memex 1:1".
4. **PDF export** del diario — rimandato (c'è export Markdown + share).
5. Le schermate social (community/eventi/gruppi) **non esistono in memex**: sono scritte ex-novo seguendo il design system memex (stessi token/widget) e i pattern dei repo event-app / IG clone.

Fonte dei file: codebase `app/` (base memex rinominata dearcocoa). Riferimenti commit: R3a `bf1c89c`, R3b+c+d `777eda0`, R4a `5be4101`, R4b questo commit.
