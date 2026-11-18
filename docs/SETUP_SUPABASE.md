# Setup Supabase + app — guida operativa

Tempo richiesto: ~15 minuti (più il deploy della edge function, ~5 min). Tutti i file citati sono nel repo.

## 1. Crea il progetto Supabase

1. Vai su [supabase.com](https://supabase.com) → New project (il piano free basta per l'MVP).
2. Una volta creato: **Settings → API** → copia `Project URL` e `Publishable / anon key`.

## 2. Esegui le migration (SQL Editor)

Nell'ordine, copiando il contenuto di ciascun file nell'SQL Editor di Supabase:

| Ordine | File | Cosa fa |
|---|---|---|
| 1 | `backend/supabase/migrations/000001_init_schema.sql` | Tabelle, trigger (profilo automatico al signup, contatore like, capienza eventi), helper `is_group_member`, realtime publication |
| 2 | `backend/supabase/migrations/000002_rls_policies.sql` | Row Level Security completa (diario privato, community, gruppi, eventi) |
| 3 | `backend/supabase/migrations/000003_storage_buckets.sql` | Bucket storage: `avatars`, `post-media`, `event-covers` (pubblici) e `journal-photos` (privato) |

In **Authentication → Providers**: Email attivo (per test rapidi puoi disattivare "Confirm email"; riattivalo in produzione).

## 3. Configura l'app

1. Apri `app/.env` e inserisci i valori del punto 1:

```
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

2. Avvia l'app:

```bash
cd app
flutter pub get
flutter run            # dispositivo/simulatore collegato
```

3. Registrati con email+password, completa l'onboarding con lo username scelto. **Oppure**, dall'app: la schermata iniziale mostra 5 account demo selezionabili con un tap (credenziali prefill nel client).

## 4. Seed dei contenuti demo

**ATTENZIONE (17/11)**: il progetto Supabase non ha ancora le migration applicate (verificato: REST su `groups` → PGRST205). Esegui nell'SQL Editor **il file unico [`backend/supabase/RUN_ALL.sql`](../backend/supabase/RUN_ALL.sql)** (schema + RLS + storage + seed in un solo paste).

- **5 account demo** con login prefill nel client: `sofia@dearcocoa.demo`, `luca@dearcocoa.demo`, `giulia@dearcocoa.demo`, `marco@dearcocoa.demo`, `elena@dearcocoa.demo` — password uguale per tutti: `Cocoa2026!`
- Profili con bio, 2 gruppi pubblici (`Morning Mindfulness`, `Journaling Circle`) con iscrizioni e messaggi di benvenuto reali
- 3 eventi futuri con programma (sort) e RSVP incrociati
- 6 post community con like e commenti tra utenti diversi

## 5. Deploy della edge function `ai-reflection`

Serve la [Supabase CLI](https://supabase.com/docs/guides/cli) installata:

```bash
supabase login
supabase link --project-ref IL_TUO_PROJECT_REF      # dalla dashboard: Settings → General

# chiave di un provider LLM OpenAI-compatible (OpenAI, o altro via AI_BASE_URL)
supabase secrets set AI_API_KEY=sk-...
# opzionali:
# supabase secrets set AI_MODEL=gpt-4o-mini
# supabase secrets set AI_BASE_URL=https://api.altro-provider.com/v1

supabase functions deploy ai-reflection
```

La funzione usa il JWT dell'utente (RLS applicata), carica voce + thread + memoria, genera la risposta e comprime la memoria ogni 6 turni. Safety (crisi/autolesività) è gestita dal system prompt: risposta supportiva e invito a contattare servizi professionali.

## 6. Checklist finale

- [ ] Migration 1-3 eseguite in ordine
- [ ] Email provider attivo
- [ ] Account di test creato dall'app
- [ ] `seed_demo.sql` eseguito
- [ ] Edge function deployata + `AI_API_KEY` impostata
- [ ] `app/.env` compilato
- [ ] `flutter run` → crea una voce, controlla che appaia in Supabase → Table Editor → `journal_entries`

## Problemi comuni

- **Schermata "DearCocoa needs setup"** → `.env` contiene ancora i placeholder.
- **"Edge function error" nel pannello AI** → funzione non deployata o `AI_API_KEY` mancante.
- **Errore capienza all'RSVP** → trigger `check_event_capacity`: l'evento è pieno (corretto).
- **Username "taken"** → vincolo unique su `profiles.username` (scegline un altro).
- **Le modifiche fatte offline non appaiono** → si sincronizzano al prossimo refresh/avvio con rete (outbox).
