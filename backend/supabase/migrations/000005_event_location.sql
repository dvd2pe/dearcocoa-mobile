-- ============================================================================
-- DearCocoa — migration 000005: eventi fisici (location) per event card ricche
--
-- Il cliente ha chiesto eventi "non solo virtuali": card con cover, avatar dei
-- partecipanti e luogo. Il backend gia' prevedeva is_virtual + cover_path +
-- bucket event-covers (000003), ma non c'era un campo per il luogo fisico.
--
-- Aggiunge events.location (nullable): mostrata nella card e nel dettaglio
-- quando is_virtual = false. Idempotente.
-- ============================================================================

alter table public.events
  add column if not exists location text;

comment on column public.events.location is
  'Venue / address for in-person events (is_virtual = false); null for virtual events.';
