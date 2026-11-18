# Note di attribuzione e licenze — DearCocoa app

## Base di codice derivata da memex (GPL-3.0)

Questa applicazione è **un lavoro derivato** da [memex-lab/memex](https://github.com/memex-lab/memex), distribuito con licenza **GNU GPL-3.0**. Il file `LICENSE` (GPL-3.0) originale è mantenuto in questo repository.

Cosa è stato fatto sulla base memex:

- Rinomina del pacchetto Dart `memex` → `dearcocoa` (pubspec, 1644 import, namespace Android `com.memexlab.memex` → `app.dearcocoa.mobile`, bundle iOS, nome canali method-channel sincronizzati su entrambi i lati, plugin nativo `agent_background_android` incluso).
- Branding utente rinominato "Memex" → "DearCocoa" nei valori di localizzazione (le chiavi interne `memex*` sono identificatori tecnici e restano tali).
- Versioni di dipendenze bloccate per compatibilità Flutter 3.35.5/Dart 3.9.2 (vedi docs/BASE_MEMEX.md).

Obblighi GPL-3.0 per la distribuzione:

1. Il codice sorgente completo dell'app distribuita deve restare disponibile in forma leggibile (questo repository privato lo soddisfa per uso interno; per distribuzione pubblica serve un repo pubblico con licenza GPL-3.0).
2. Le modifiche restano GPL-3.0: nessuna restrizione aggiuntiva può essere imposta a chi riceve il software.
3. Copyright originale memex conservato (vedi LICENSE e intestazioni dei file sorgente).

Se il cliente dispone di un accordo commerciale (dual licensing) con memex-lab, questa nota può essere aggiornata di conseguenza.

## Altri package di terze parti principali

| Package | Licenza | Uso |
|---|---|---|
| flutter, engine, plugins first-party | BSD-3 | framework |
| google_fonts | MIT | font Bricolage Grotesque + Inter (OFL) |
| drift / drift_flutter / sqlite3_flutter_libs | MIT | database locale |
| go_router, provider | MIT/BSD | routing e stato |
| fl_chart | Apache-2.0 | grafici mood/insight |
| local_auth | BSD-3 | app lock biometrico |
| flutter_js | MIT | runtime JS skill agente |
| flutter_markdown | MIT (discontinuato, in uso) | rendering markdown |
| wechat_assets_picker / photo_manager | Apache-2.0 | picker media |
| webview_flutter | BSD-3 | card HTML timeline |

Il file `pubspec.lock` contiene l'elenco completo con licenze rilevabili via `flutter pub deps` / `dart pub license` (`flutter pub licenses` nelle versioni recenti).
