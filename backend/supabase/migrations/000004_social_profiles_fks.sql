-- ============================================================================
-- DearCocoa — migration 000004: social FK -> public.profiles
--
-- CAUSA ROOT degli errori "Could not load events / community":
-- PostgREST non riesce a risolvere gli embed  profiles!space_posts_user_id_fkey
-- e profiles!events_created_by_fkey perche' le FK puntano ad auth.users (schema
-- non esposto all'API), quindi la relazione 'space_posts -> profiles' non esiste
-- nello schema cache (errore PGRST200) e l'intera query REST torna 400.
--
-- FIX (pattern Supabase standard): le FK dei social table puntano direttamente
-- a public.profiles(id). I nomi dei constraint restano GLI STESSI usati come
-- hint nel client (space_posts_user_id_fkey, events_created_by_fkey, ...).
-- La catena cascade resta integra: profiles.id -> auth.users(id) on delete cascade.
--
-- Idempotente: puo' essere rilanciata senza danni.
-- ============================================================================

-- 1) backfill: profili mancanti per utenti che ne sono sprovvisti
--    (necessario prima di aggiungere le FK, altrimenti le righe orfane
--    bloccherebbero l'ALTER TABLE)
insert into public.profiles (id, username, display_name)
select u.id,
       coalesce(nullif(split_part(u.email, '@', 1), ''), 'user') || '_' ||
         substr(replace(u.id::text, '-', ''), 1, 6),
       coalesce(nullif(split_part(u.email, '@', 1), ''), 'Cocoa friend')
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

-- username univoco: nel raro caso di collisione cambia username suffissandolo
update public.profiles p
set username = p.username || '_' || substr(replace(p.id::text, '-', ''), 1, 6)
where exists (
  select 1 from public.profiles q
  where q.username = p.username and q.id <> p.id
);

-- 2) re-point delle FK a public.profiles mantenendo i nomi usati dal client
alter table public.space_posts    drop constraint if exists space_posts_user_id_fkey;
alter table public.space_posts    add constraint space_posts_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.post_comments  drop constraint if exists post_comments_user_id_fkey;
alter table public.post_comments  add constraint post_comments_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.post_likes     drop constraint if exists post_likes_user_id_fkey;
alter table public.post_likes     add constraint post_likes_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.group_members  drop constraint if exists group_members_user_id_fkey;
alter table public.group_members  add constraint group_members_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.group_messages drop constraint if exists group_messages_user_id_fkey;
alter table public.group_messages add constraint group_messages_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.event_rsvps    drop constraint if exists event_rsvps_user_id_fkey;
alter table public.event_rsvps    add constraint event_rsvps_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.events         drop constraint if exists events_created_by_fkey;
alter table public.events         add constraint events_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete cascade;

-- 3) nota: profiles.id -> auth.users(id) resta l'unica FK verso auth
