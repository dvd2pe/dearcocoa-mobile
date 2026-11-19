-- DearCocoa — RUN_ALL (17/11/2026): esegui QUESTO UNICO file nell'SQL Editor.
-- Contiene: schema completo (000001) + RLS (000002) + storage (000003) + seed demo v2/v3 + 000004 FK profiles + 000005 event location.
-- Idempotente dove possibile. Dopo questo file l'app è pronta con 5 account demo.

-- ============================================================================
-- DearCocoa — migration 000001: schema iniziale
-- Eseguire nell'SQL Editor di Supabase (o con supabase db push).
-- Tabelle: profili, diario privato, riflessioni AI, memoria AI, gruppi,
-- messaggi, community (post/like/commenti), eventi virtuali + programma.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Profili (1:1 con auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text not null unique check (char_length(username) between 3 and 30),
  display_name text not null default '',
  bio          text not null default '',
  avatar_path  text,
  onboarded    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Diario privato (offline-first: il client tiene una copia locale + outbox)
-- ---------------------------------------------------------------------------
create table public.journal_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  title       text not null default '',
  body        text not null default '',
  mood        smallint check (mood between 1 and 5),        -- 1 molto basso .. 5 ottimo
  entry_date  date not null default current_date,
  is_private  boolean not null default true,
  photo_paths text[] not null default '{}',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz                                    -- soft delete per sync
);
create index journal_entries_user_date_idx on public.journal_entries (user_id, entry_date desc);
create index journal_entries_user_updated_idx on public.journal_entries (user_id, updated_at desc);

-- ---------------------------------------------------------------------------
-- Riflessioni AI: thread 1:1 per entry (ruoli user/assistant)
-- ---------------------------------------------------------------------------
create table public.ai_reflections (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references public.journal_entries (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       text not null check (role in ('user', 'assistant')),
  content    text not null,
  created_at timestamptz not null default now()
);
create index ai_reflections_entry_idx on public.ai_reflections (entry_id, created_at);

-- ---------------------------------------------------------------------------
-- Memoria AI persistente (riassunti compressi, fatti, preferenze)
-- ---------------------------------------------------------------------------
create table public.ai_memory (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  kind        text not null default 'summary' check (kind in ('summary', 'fact', 'preference')),
  content     text not null,
  importance  smallint not null default 2 check (importance between 1 and 5),
  source_entry uuid references public.journal_entries (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index ai_memory_user_idx on public.ai_memory (user_id, importance desc, created_at desc);

-- ---------------------------------------------------------------------------
-- Gruppi
-- ---------------------------------------------------------------------------
create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 3 and 60),
  description text not null default '',
  is_public   boolean not null default true,
  created_by  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  role      text not null default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table public.group_messages (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  content       text not null check (char_length(content) between 1 and 2000),
  author_name   text not null default '',
  author_avatar text,
  created_at    timestamptz not null default now()
);
create index group_messages_group_idx on public.group_messages (group_id, created_at);

-- ---------------------------------------------------------------------------
-- Community: post (group_id null = feed globale), like, commenti
-- ---------------------------------------------------------------------------
create table public.space_posts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  group_id    uuid references public.groups (id) on delete cascade,
  content     text not null check (char_length(content) between 1 and 3000),
  media_paths text[] not null default '{}',
  like_count  int not null default 0,
  created_at  timestamptz not null default now()
);
create index space_posts_feed_idx on public.space_posts (group_id, created_at desc);

create table public.post_likes (
  post_id    uuid not null references public.space_posts (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.post_comments (
  id            uuid primary key default gen_random_uuid(),
  post_id       uuid not null references public.space_posts (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  content       text not null check (char_length(content) between 1 and 1000),
  author_name   text not null default '',
  author_avatar text,
  created_at    timestamptz not null default now()
);
create index post_comments_post_idx on public.post_comments (post_id, created_at);

-- ---------------------------------------------------------------------------
-- Eventi virtuali
-- ---------------------------------------------------------------------------
create table public.events (
  id          uuid primary key default gen_random_uuid(),
  created_by  uuid not null references auth.users (id) on delete cascade,
  title       text not null check (char_length(title) between 3 and 120),
  description text not null default '',
  category    text not null default 'community'
              check (category in ('wellness', 'workshop', 'community', 'meditation', 'social')),
  cover_path  text,
  is_virtual  boolean not null default true,
  meeting_url text,
  starts_at   timestamptz not null,
  ends_at     timestamptz,
  capacity    int not null default 100 check (capacity between 1 and 10000),
  created_at  timestamptz not null default now()
);
create index events_starts_idx on public.events (starts_at);

create table public.event_rsvps (
  event_id   uuid not null references public.events (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  status     text not null default 'going' check (status in ('going', 'interested', 'cancelled')),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table public.event_program (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events (id) on delete cascade,
  title       text not null,
  speaker     text not null default '',
  description text not null default '',
  starts_at   timestamptz not null,
  sort        int not null default 0
);
create index event_program_event_idx on public.event_program (event_id, sort);

-- ============================================================================
-- Funzioni e trigger
-- ============================================================================

-- updated_at automatico su profiles e journal_entries
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_updated before update on public.profiles
for each row execute function public.touch_updated_at();
create trigger trg_journal_updated before update on public.journal_entries
for each row execute function public.touch_updated_at();

-- profilo automatico al signup (username da email + suffix casuale)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    split_part(new.email, '@', 1) || '_' || substr(replace(new.id::text, '-', ''), 1, 6),
    split_part(new.email, '@', 1)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- contatore like (incremento/decremento atomico)
create or replace function public.on_like_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT') then
    update public.space_posts set like_count = like_count + 1 where id = new.post_id;
  elsif (tg_op = 'DELETE') then
    update public.space_posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$$;

create trigger trg_like_change
after insert or delete on public.post_likes
for each row execute function public.on_like_change();

-- capienza eventi: rifiuta RSVP oltre capacity
create or replace function public.check_event_capacity() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_capacity int;
  v_count int;
begin
  if new.status = 'cancelled' then return new; end if;
  select capacity into v_capacity from public.events where id = new.event_id;
  select count(*) into v_count from public.event_rsvps
  where event_id = new.event_id and status = 'going' and user_id <> new.user_id;
  if v_count >= v_capacity then
    raise exception 'Evento al completo (% posti)', v_capacity using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_event_capacity
before insert or update on public.event_rsvps
for each row execute function public.check_event_capacity();

-- helper RLS: appartenenza a un gruppo (security definer per evitare ricorsione)
create or replace function public.is_group_member(gid uuid, uid uuid default null)
returns boolean
language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid
      and user_id = coalesce(uid, auth.uid())
  );
$$;

-- ============================================================================
-- Realtime: repliche per chat e commenti
-- ============================================================================
alter publication supabase_realtime add table public.group_messages;
alter publication supabase_realtime add table public.post_comments;
alter publication supabase_realtime add table public.space_posts;

-- ============================================================ RLS ===
-- ============================================================================
-- DearCocoa — migration 000002: Row Level Security
-- Principio: il diario, le riflessioni AI e la memoria AI sono privati;
-- community/gruppi/eventi visibili ai membri; ogni utente scrive solo per sé.
-- ============================================================================

alter table public.profiles        enable row level security;
alter table public.journal_entries enable row level security;
alter table public.ai_reflections  enable row level security;
alter table public.ai_memory       enable row level security;
alter table public.groups          enable row level security;
alter table public.group_members   enable row level security;
alter table public.group_messages  enable row level security;
alter table public.space_posts     enable row level security;
alter table public.post_likes      enable row level security;
alter table public.post_comments   enable row level security;
alter table public.events          enable row level security;
alter table public.event_rsvps     enable row level security;
alter table public.event_program   enable row level security;

-- ---------------------------------------------------------------------------
-- Profili: leggibili a tutti gli autenticati, modificabili solo dal proprietario
-- ---------------------------------------------------------------------------
create policy "profiles_select" on public.profiles for select
  using (true);
create policy "profiles_insert_self" on public.profiles for insert
  with check (auth.uid() = id);
create policy "profiles_update_self" on public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- Diario privato: solo il proprietario (nemmeno in lettura ad altri)
-- ---------------------------------------------------------------------------
create policy "journal_owner_all" on public.journal_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "ai_reflections_owner_all" on public.ai_reflections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "ai_memory_owner_all" on public.ai_memory
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Gruppi: pubblici visibili a tutti; privati solo ai membri e al creatore
-- ---------------------------------------------------------------------------
create policy "groups_select" on public.groups for select
  using (is_public or public.is_group_member(id) or created_by = auth.uid());

create policy "groups_insert_self" on public.groups for insert
  with check (auth.uid() = created_by);

create policy "groups_update_admin" on public.groups for update
  using (
    created_by = auth.uid()
    or exists (
      select 1 from public.group_members m
      where m.group_id = id and m.user_id = auth.uid() and m.role = 'admin'
    )
  ) with check (
    created_by = auth.uid()
    or exists (
      select 1 from public.group_members m
      where m.group_id = id and m.user_id = auth.uid() and m.role = 'admin'
    )
  );

create policy "groups_delete_creator" on public.groups for delete
  using (created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- Membri: lista visibile ai membri e per i gruppi pubblici; iscrizioni
-- autonome sui gruppi pubblici; gli admin possono aggiungere/rimuovere
-- ---------------------------------------------------------------------------
create policy "members_select" on public.group_members for select
  using (
    user_id = auth.uid()
    or public.is_group_member(group_id)
    or exists (select 1 from public.groups g where g.id = group_id and g.is_public)
  );

create policy "members_insert" on public.group_members for insert
  with check (
    user_id = auth.uid()
    and (
      exists (select 1 from public.groups g where g.id = group_id and g.is_public)
      or public.is_group_member(group_id)
    )
  );

create policy "members_insert_by_admin" on public.group_members for insert
  with check (
    user_id <> auth.uid()
    and exists (
      select 1 from public.group_members m
      where m.group_id = group_id and m.user_id = auth.uid() and m.role = 'admin'
    )
  );

create policy "members_delete_self" on public.group_members for delete
  using (user_id = auth.uid());

create policy "members_delete_by_admin" on public.group_members for delete
  using (
    exists (
      select 1 from public.group_members m
      where m.group_id = group_id and m.user_id = auth.uid() and m.role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- Messaggi di gruppo: solo i membri leggono e scrivono per sé
-- ---------------------------------------------------------------------------
create policy "messages_select_member" on public.group_messages for select
  using (public.is_group_member(group_id));

create policy "messages_insert_member" on public.group_messages for insert
  with check (auth.uid() = user_id and public.is_group_member(group_id));

create policy "messages_delete_author_or_admin" on public.group_messages for delete
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.group_members m
      where m.group_id = group_id and m.user_id = auth.uid() and m.role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- Post community: feed globale aperto, post di gruppo solo ai membri
-- ---------------------------------------------------------------------------
create policy "posts_select" on public.space_posts for select
  using (group_id is null or public.is_group_member(group_id));

create policy "posts_insert" on public.space_posts for insert
  with check (auth.uid() = user_id and (group_id is null or public.is_group_member(group_id)));

create policy "posts_update_author_or_admin" on public.space_posts for update
  using (
    user_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.group_members m
      where m.group_id = group_id and m.user_id = auth.uid() and m.role = 'admin'
    ))
  ) with check (
    user_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.group_members m
      where m.group_id = group_id and m.user_id = auth.uid() and m.role = 'admin'
    ))
  );

create policy "posts_delete_author_or_admin" on public.space_posts for delete
  using (
    user_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.group_members m
      where m.group_id = group_id and m.user_id = auth.uid() and m.role = 'admin'
    ))
  );

-- ---------------------------------------------------------------------------
-- Like e commenti: visibili dove il post è visibile; ognuno il proprio voto
-- ---------------------------------------------------------------------------
create policy "likes_select" on public.post_likes for select
  using (
    exists (
      select 1 from public.space_posts p
      where p.id = post_id and (p.group_id is null or public.is_group_member(p.group_id))
    )
  );

create policy "likes_insert_self" on public.post_likes for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.space_posts p
      where p.id = post_id and (p.group_id is null or public.is_group_member(p.group_id))
    )
  );

create policy "likes_delete_self" on public.post_likes for delete
  using (auth.uid() = user_id);

create policy "comments_select" on public.post_comments for select
  using (
    exists (
      select 1 from public.space_posts p
      where p.id = post_id and (p.group_id is null or public.is_group_member(p.group_id))
    )
  );

create policy "comments_insert_member" on public.post_comments for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.space_posts p
      where p.id = post_id and (p.group_id is null or public.is_group_member(p.group_id))
    )
  );

create policy "comments_delete_author_or_admin" on public.post_comments for delete
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.space_posts p
      join public.group_members m on m.group_id = p.group_id
      where p.id = post_id and m.user_id = auth.uid() and m.role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- Eventi: tutti li vedono (e si iscrivono), il creatore li gestisce
-- ---------------------------------------------------------------------------
create policy "events_select" on public.events for select
  using (true);

create policy "events_insert_self" on public.events for insert
  with check (auth.uid() = created_by);

create policy "events_update_creator" on public.events for update
  using (auth.uid() = created_by) with check (auth.uid() = created_by);

create policy "events_delete_creator" on public.events for delete
  using (auth.uid() = created_by);

create policy "rsvps_select" on public.event_rsvps for select
  using (true);

create policy "rsvps_insert_self" on public.event_rsvps for insert
  with check (auth.uid() = user_id);

create policy "rsvps_update_self" on public.event_rsvps for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "rsvps_delete_self" on public.event_rsvps for delete
  using (auth.uid() = user_id);

create policy "program_select" on public.event_program for select
  using (true);

create policy "program_manage_creator" on public.event_program for all
  using (
    exists (select 1 from public.events e where e.id = event_id and e.created_by = auth.uid())
  ) with check (
    exists (select 1 from public.events e where e.id = event_id and e.created_by = auth.uid())
  );

-- ======================================================== STORAGE ===
-- ============================================================================
-- DearCocoa — migration 000003: storage buckets e policy
-- Bucket: avatars e post-media/event-covers pubblici in lettura;
-- journal-photos PRIVATO (accessibile solo al proprietario del path).
-- ============================================================================

insert into storage.buckets (id, name, public)
values
  ('avatars',        'avatars',        true),
  ('journal-photos', 'journal-photos', false),
  ('post-media',     'post-media',     true),
  ('event-covers',   'event-covers',   true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- avatars: tutti leggono; ognuno scrive solo nella propria cartella <uid>/
-- ---------------------------------------------------------------------------
create policy "avatars_public_read" on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatars_owner_write" on storage.objects for insert
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_update" on storage.objects for update
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_delete" on storage.objects for delete
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- journal-photos: PRIVATO, solo il proprietario della cartella <uid>/
-- ---------------------------------------------------------------------------
create policy "journal_photos_owner_all_select" on storage.objects for select
  using (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "journal_photos_owner_insert" on storage.objects for insert
  with check (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "journal_photos_owner_update" on storage.objects for update
  using (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "journal_photos_owner_delete" on storage.objects for delete
  using (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- post-media ed event-covers: lettura pubblica, scrittura per autenticati
-- (i post/eventi sono moderabili dagli admin a livello di tabella)
-- ---------------------------------------------------------------------------
create policy "post_media_public_read" on storage.objects for select
  using (bucket_id = 'post-media');

create policy "post_media_auth_write" on storage.objects for insert
  with check (bucket_id = 'post-media' and auth.role() = 'authenticated');

create policy "post_media_owner_update" on storage.objects for update
  using (bucket_id = 'post-media' and owner = auth.uid());

create policy "post_media_owner_delete" on storage.objects for delete
  using (bucket_id = 'post-media' and owner = auth.uid());

create policy "event_covers_public_read" on storage.objects for select
  using (bucket_id = 'event-covers');

create policy "event_covers_auth_write" on storage.objects for insert
  with check (bucket_id = 'event-covers' and auth.role() = 'authenticated');

create policy "event_covers_owner_update" on storage.objects for update
  using (bucket_id = 'event-covers' and owner = auth.uid());

create policy "event_covers_owner_delete" on storage.objects for delete
  using (bucket_id = 'event-covers' and owner = auth.uid());

-- ============================================================ SEED ===
-- ============================================================================
-- DearCocoa — seed demo v2 (17/11/2026)
-- Crea 5 account demo con credenziali prefill + contenuti interconnessi:
-- profili, 2 gruppi con messaggi, 3 eventi con programma e RSVP, 6 post
-- community con like e commenti.
--
-- CREDENZIALI DEMO (prefill nel client, login con un tap):
--   sofia@dearcocoa.demo  / Cocoa2026!  (Sofia Rossi)
--   luca@dearcocoa.demo   / Cocoa2026!  (Luca Bianchi)
--   giulia@dearcocoa.demo / Cocoa2026!  (Giulia Ferrari)
--   marco@dearcocoa.demo  / Cocoa2026!  (Marco Conti)
--   elena@dearcocoa.demo  / Cocoa2026!  (Elena Moretti)
--
-- Idempotente: rilanciarlo non duplica nulla.
-- Richiede pgcrypto (default attivo su Supabase).
-- ============================================================================

do $$
declare
  u_sofia uuid; u_luca uuid; u_giulia uuid; u_marco uuid; u_elena uuid;
  g_morning uuid; g_circle uuid;
  e_moon uuid; e_breath uuid; e_write uuid;
begin
  -- ------------------------------------------------------------ utenti auth
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, last_sign_in_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated',
    'sofia@dearcocoa.demo', extensions.crypt('Cocoa2026!', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}', '{"username":"sofia_r"}',
    now() - interval '30 days', now() - interval '30 days', '', '', '', '',
    now() - interval '1 day')
  on conflict (email) do update set encrypted_password = excluded.encrypted_password,
      email_confirmed_at = now()
  returning id into u_sofia;
  if u_sofia is null then
    select id into u_sofia from auth.users where email = 'sofia@dearcocoa.demo';
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, last_sign_in_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated',
    'luca@dearcocoa.demo', extensions.crypt('Cocoa2026!', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}', '{"username":"luca_b"}',
    now() - interval '28 days', now() - interval '28 days', '', '', '', '',
    now() - interval '2 days')
  on conflict (email) do update set encrypted_password = excluded.encrypted_password,
      email_confirmed_at = now()
  returning id into u_luca;
  if u_luca is null then
    select id into u_luca from auth.users where email = 'luca@dearcocoa.demo';
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, last_sign_in_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated',
    'giulia@dearcocoa.demo', extensions.crypt('Cocoa2026!', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}', '{"username":"giulia_f"}',
    now() - interval '25 days', now() - interval '25 days', '', '', '', '',
    now() - interval '3 days')
  on conflict (email) do update set encrypted_password = excluded.encrypted_password,
      email_confirmed_at = now()
  returning id into u_giulia;
  if u_giulia is null then
    select id into u_giulia from auth.users where email = 'giulia@dearcocoa.demo';
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, last_sign_in_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated',
    'marco@dearcocoa.demo', extensions.crypt('Cocoa2026!', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}', '{"username":"marco_c"}',
    now() - interval '20 days', now() - interval '20 days', '', '', '', '',
    now() - interval '4 days')
  on conflict (email) do update set encrypted_password = excluded.encrypted_password,
      email_confirmed_at = now()
  returning id into u_marco;
  if u_marco is null then
    select id into u_marco from auth.users where email = 'marco@dearcocoa.demo';
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, last_sign_in_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated',
    'elena@dearcocoa.demo', extensions.crypt('Cocoa2026!', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}', '{"username":"elena_m"}',
    now() - interval '18 days', now() - interval '18 days', '', '', '', '',
    now() - interval '5 days')
  on conflict (email) do update set encrypted_password = excluded.encrypted_password,
      email_confirmed_at = now()
  returning id into u_elena;
  if u_elena is null then
    select id into u_elena from auth.users where email = 'elena@dearcocoa.demo';
  end if;

  -- -------------------------------------------------------------- profili
  insert into public.profiles (id, username, display_name, bio, onboarded) values
    (u_sofia,  'sofia_r',  'Sofia Rossi',   'Morning pages believer. Tea over coffee.', true),
    (u_luca,   'luca_b',   'Luca Bianchi',  'Walking meditation & night journaling.', true),
    (u_giulia, 'giulia_f', 'Giulia Ferrari','Gratitude lists changed my life.', true),
    (u_marco,  'marco_c',  'Marco Conti',   'Runner. Tracking mood since January.', true),
    (u_elena,  'elena_m',  'Elena Moretti', 'Here for gentle accountability.', true)
  on conflict (id) do update set display_name = excluded.display_name,
      bio = excluded.bio, onboarded = true;

  -- -------------------------------------------------------------- gruppi
  insert into public.groups (name, description, is_public, created_by)
  values ('Morning Mindfulness', 'Gentle morning check-ins and gratitude rituals.', true, u_sofia)
  on conflict do nothing
  returning id into g_morning;
  if g_morning is null then
    select id into g_morning from public.groups where name = 'Morning Mindfulness';
  end if;

  insert into public.groups (name, description, is_public, created_by)
  values ('Journaling Circle', 'Weekly prompts and sharing circles for writers.', true, u_giulia)
  on conflict do nothing
  returning id into g_circle;
  if g_circle is null then
    select id into g_circle from public.groups where name = 'Journaling Circle';
  end if;

  insert into public.group_members (group_id, user_id, role) values
    (g_morning, u_sofia, 'admin'),  (g_morning, u_luca, 'member'),
    (g_morning, u_giulia, 'member'),(g_morning, u_elena, 'member'),
    (g_circle, u_giulia, 'admin'),  (g_circle, u_sofia, 'member'),
    (g_circle, u_marco, 'member'),  (g_circle, u_elena, 'member')
  on conflict (group_id, user_id) do nothing;

  insert into public.group_messages (group_id, user_id, content, author_name, created_at) values
    (g_morning, u_sofia, 'Good morning everyone 🌤 Starting the week with three things I am grateful for: morning light, my dog, and this group.', 'Sofia Rossi', now() - interval '2 days'),
    (g_morning, u_luca, 'I did a 20-minute walk before sunrise today. The quiet made the journaling easier afterwards.', 'Luca Bianchi', now() - interval '2 days' + interval '37 minutes'),
    (g_morning, u_elena, 'This group keeps me consistent. Day 12 of check-ins in a row!', 'Elena Moretti', now() - interval '1 day'),
    (g_circle, u_giulia, 'New prompt for the week: describe a moment you felt proud, small or big. Write it as a scene.', 'Giulia Ferrari', now() - interval '3 days'),
    (g_circle, u_marco, 'I wrote about finishing my first 10k. Turns out pride feels warm, not loud.', 'Marco Conti', now() - interval '3 days' + interval '52 minutes'),
    (g_circle, u_sofia, 'Loved that prompt. Sharing mine tonight after work.', 'Sofia Rossi', now() - interval '2 days')
  on conflict do nothing;

  -- -------------------------------------------------------------- eventi
  insert into public.events (created_by, title, description, category, is_virtual,
      meeting_url, starts_at, ends_at, capacity)
  values (u_sofia, 'Full Moon Journaling Night',
      'A calm evening of guided prompts, candle light and shared reflection. Bring your favourite notebook.',
      'meditation', true, 'https://meet.dearcocoa.app/full-moon',
      now() + interval '5 days', now() + interval '5 days' + interval '90 minutes', 40)
  on conflict do nothing
  returning id into e_moon;
  if e_moon is null then
    select id into e_moon from public.events
    where title = 'Full Moon Journaling Night' and starts_at > now() limit 1;
  end if;

  insert into public.events (created_by, title, description, category, is_virtual,
      meeting_url, starts_at, ends_at, capacity)
  values (u_marco, 'Breathwork for Anxious Days',
      'A practical 45-minute session: grounding breath patterns you can reuse whenever the day gets loud.',
      'wellness', true, 'https://meet.dearcocoa.app/breathwork',
      now() + interval '9 days', now() + interval '9 days' + interval '45 minutes', 100)
  on conflict do nothing
  returning id into e_breath;
  if e_breath is null then
    select id into e_breath from public.events
    where title = 'Breathwork for Anxious Days' and starts_at > now() limit 1;
  end if;

  insert into public.events (created_by, title, description, category, is_virtual,
      meeting_url, starts_at, ends_at, capacity)
  values (u_giulia, 'Sunday Writing Circle',
      'Weekly circle for gentle accountability: 25 minutes of silent writing, then optional sharing.',
      'workshop', true, 'https://meet.dearcocoa.app/circle',
      now() + interval '3 days', now() + interval '3 days' + interval '60 minutes', 25)
  on conflict do nothing
  returning id into e_write;
  if e_write is null then
    select id into e_write from public.events
    where title = 'Sunday Writing Circle' and starts_at > now() limit 1;
  end if;

  insert into public.event_program (event_id, title, speaker, description, starts_at, sort) values
    (e_moon, 'Welcome & grounding', 'Sofia Rossi', 'Short arrival ritual: settle, breathe, arrive on the page.', now() + interval '5 days', 0),
    (e_moon, 'Guided prompts', 'Sofia Rossi', 'Three moon-themed prompts, written in silence with soft music.', now() + interval '5 days' + interval '15 minutes', 1),
    (e_moon, 'Optional sharing', 'Everyone', 'Share one line if you feel like it. Silence is welcome too.', now() + interval '5 days' + interval '55 minutes', 2),
    (e_breath, 'Physiology of breath', 'Marco Conti', 'Why long exhales calm the nervous system, in plain words.', now() + interval '9 days', 0),
    (e_breath, 'Guided practice', 'Marco Conti', '4-7-8 and box breathing, practised together.', now() + interval '9 days' + interval '10 minutes', 1)
  on conflict do nothing;

  insert into public.event_rsvps (event_id, user_id, status) values
    (e_moon, u_luca, 'going'),   (e_moon, u_giulia, 'going'),   (e_moon, u_elena, 'interested'),
    (e_breath, u_sofia, 'going'),(e_breath, u_elena, 'going'),  (e_breath, u_giulia, 'interested'),
    (e_write, u_sofia, 'going'), (e_write, u_marco, 'going'),   (e_write, u_elena, 'going')
  on conflict (event_id, user_id) do nothing;

  -- ----------------------------------------------------------- community
  insert into public.space_posts (user_id, content, created_at) values
    (u_sofia, 'Week 3 of morning pages. Some days it is nonsense, some days it is gold — apparently both count. 🌱', now() - interval '3 days'),
    (u_marco, 'Mood tracker says October was calmer than September. Small proof that the evening walks are doing something.', now() - interval '2 days'),
    (u_giulia, 'Tip for anyone stuck: write three lines only. Tiny entries kept me going for a whole month.', now() - interval '2 days' + interval '4 hours'),
    (u_luca, 'Tried journaling in the park today. The pigeons had opinions about my handwriting.', now() - interval '1 day'),
    (u_elena, 'Day 12 of daily check-ins. The streak view is quietly the best motivation I have found.', now() - interval '18 hours'),
    (u_giulia, 'Reminder: the Sunday Writing Circle is open. Come as you are, write as you can. ☕', now() - interval '5 hours')
  on conflict do nothing;

  -- like deterministici per prefisso di contenuto
  insert into public.post_likes (post_id, user_id)
  select p.id, a.id
  from (values
      ('Week 3 of morning pages',  'luca@dearcocoa.demo'),
      ('Week 3 of morning pages',  'elena@dearcocoa.demo'),
      ('Week 3 of morning pages',  'giulia@dearcocoa.demo'),
      ('Mood tracker says October','giulia@dearcocoa.demo'),
      ('Mood tracker says October','sofia@dearcocoa.demo'),
      ('Tip for anyone stuck',     'sofia@dearcocoa.demo'),
      ('Tip for anyone stuck',     'elena@dearcocoa.demo'),
      ('Tried journaling in the park','marco@dearcocoa.demo'),
      ('Day 12 of daily check-ins','sofia@dearcocoa.demo'),
      ('Day 12 of daily check-ins','giulia@dearcocoa.demo'),
      ('Reminder: the Sunday Writing Circle','luca@dearcocoa.demo'),
      ('Reminder: the Sunday Writing Circle','marco@dearcocoa.demo')
  ) as pairs(prefix, liker)
  join public.space_posts p on p.content like pairs.prefix || '%'
  join auth.users a on a.email = pairs.liker
  where not exists (
    select 1 from public.post_likes pl
    where pl.post_id = p.id and pl.user_id = a.id);
  update public.space_posts p set like_count = (
    select count(*) from public.post_likes pl where pl.post_id = p.id);

  -- commenti reali incrociati
  insert into public.post_comments (post_id, user_id, content, author_name, created_at)
  select p.id, a.id, 'Both count. Keep going 💛', 'Luca Bianchi', now() - interval '2 days' + interval '1 hour'
  from public.space_posts p join auth.users a on a.email = 'luca@dearcocoa.demo'
  where p.content like 'Week 3 of morning pages%'
    and not exists (select 1 from public.post_comments c where c.post_id = p.id);

  insert into public.post_comments (post_id, user_id, content, author_name, created_at)
  select p.id, a.id, 'The data does not lie! 📈 Which tracker view is that?', 'Sofia Rossi', now() - interval '1 day' + interval '2 hours'
  from public.space_posts p join auth.users a on a.email = 'sofia@dearcocoa.demo'
  where p.content like 'Mood tracker says October%'
    and not exists (select 1 from public.post_comments c where c.post_id = p.id);

  insert into public.post_comments (post_id, user_id, content, author_name, created_at)
  select p.id, a.id, 'Three lines is my maximum some days — and it still works.', 'Elena Moretti', now() - interval '20 hours'
  from public.space_posts p join auth.users a on a.email = 'elena@dearcocoa.demo'
  where p.content like 'Tip for anyone stuck%'
    and not exists (select 1 from public.post_comments c where c.post_id = p.id);

  insert into public.post_comments (post_id, user_id, content, author_name, created_at)
  select p.id, a.id, 'The pigeons are the harshest editors. 😄', 'Giulia Ferrari', now() - interval '9 hours'
  from public.space_posts p join auth.users a on a.email = 'giulia@dearcocoa.demo'
  where p.content like 'Tried journaling in the park%'
    and not exists (select 1 from public.post_comments c where c.post_id = p.id);

  update public.space_posts p set like_count = (
    select count(*) from public.post_likes pl where pl.post_id = p.id);

  raise notice 'Seed demo v2 completato: 5 utenti, 2 gruppi, 3 eventi, 6 post.';
end $$;
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


-- (000004 appended sopra: FK social -> public.profiles, fix PGRST200 embed)


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


-- ============================================================================
-- Seed v3 (20/11/2026): contenuti realistici per l'app "produzione".
--  - avatar profili, cover eventi, un evento fisico con location (migration 000005)
--  - post community con foto (media_paths), messaggi gruppo extra
--  - tutto idempotente: guardie not exists / update per titolo
-- ============================================================================
do $$
declare
  u_sofia uuid; u_luca uuid; u_giulia uuid; u_marco uuid; u_elena uuid;
  g_morning uuid; g_circle uuid; g_walk uuid;
  e_park uuid;
begin
  select id into u_sofia  from auth.users where email = 'sofia@dearcocoa.demo';
  select id into u_luca   from auth.users where email = 'luca@dearcocoa.demo';
  select id into u_giulia from auth.users where email = 'giulia@dearcocoa.demo';
  select id into u_marco  from auth.users where email = 'marco@dearcocoa.demo';
  select id into u_elena  from auth.users where email = 'elena@dearcocoa.demo';
  select id into g_morning from public.groups where name = 'Morning Mindfulness' limit 1;

  -- ------------------------------------------------------------ avatar profili
  update public.profiles set avatar_path = 'https://picsum.photos/seed/cocoa-sofia/240/240'  where id = u_sofia  and (avatar_path is null or avatar_path = '');
  update public.profiles set avatar_path = 'https://picsum.photos/seed/cocoa-luca/240/240'   where id = u_luca   and (avatar_path is null or avatar_path = '');
  update public.profiles set avatar_path = 'https://picsum.photos/seed/cocoa-giulia/240/240' where id = u_giulia and (avatar_path is null or avatar_path = '');
  update public.profiles set avatar_path = 'https://picsum.photos/seed/cocoa-marco/240/240'  where id = u_marco  and (avatar_path is null or avatar_path = '');
  update public.profiles set avatar_path = 'https://picsum.photos/seed/cocoa-elena/240/240'  where id = u_elena  and (avatar_path is null or avatar_path = '');

  -- ------------------------------------------------------------ cover eventi
  update public.events set cover_path = 'https://picsum.photos/seed/cocoa-moon/800/450'
    where title = 'Full Moon Journaling Night';
  update public.events set cover_path = 'https://picsum.photos/seed/cocoa-breath/800/450'
    where title = 'Breathwork for Anxious Days';
  update public.events set cover_path = 'https://picsum.photos/seed/cocoa-circle/800/450'
    where title = 'Sunday Writing Circle';

  -- ------------------------------------------------------------ evento fisico
  select id into e_park from public.events
    where title = 'Sunrise Park Walk & Coffee' limit 1;
  if e_park is null then
    insert into public.events (created_by, title, description, category, is_virtual,
        location, cover_path, starts_at, ends_at, capacity)
    values (u_luca, 'Sunrise Park Walk & Coffee',
        'A slow 5 km walk in the park, then coffee at the kiosk. We meet at the north gate — look for the cocoa-brown tote bag.',
        'social', false, 'Villa Borghese, north gate — Roma',
        'https://picsum.photos/seed/cocoa-park/800/450',
        now() + interval '7 days', now() + interval '7 days' + interval '2 hours', 15)
    returning id into e_park;
  end if;

  insert into public.event_rsvps (event_id, user_id, status) values
    (e_park, u_sofia, 'going'), (e_park, u_giulia, 'going'),
    (e_park, u_marco, 'going'), (e_park, u_elena, 'interested')
  on conflict (event_id, user_id) do nothing;

  insert into public.event_program (event_id, title, speaker, description, starts_at, sort) values
    (e_park, 'Meet & slow walk', 'Luca Bianchi', 'Two loops of the avenue at talking pace.', now() + interval '7 days', 0),
    (e_park, 'Coffee & journals', 'Everyone', 'Ten minutes of freewriting with coffee in hand.', now() + interval '7 days' + interval '70 minutes', 1)
  on conflict do nothing;

  -- ------------------------------------------------------- terzo gruppo
  select id into g_walk from public.groups where name = 'Park Run Buddies' limit 1;
  if g_walk is null then
    insert into public.groups (name, description, is_public, created_by)
    values ('Park Run Buddies', 'Saturday runs and walks, all paces welcome.', true, u_luca)
    returning id into g_walk;
  end if;

  insert into public.group_members (group_id, user_id, role) values
    (g_walk, u_luca, 'admin'), (g_walk, u_marco, 'member'),
    (g_walk, u_sofia, 'member'), (g_walk, u_elena, 'member')
  on conflict (group_id, user_id) do nothing;

  insert into public.group_messages (group_id, user_id, content, author_name, created_at)
  select g_walk, u_marco,
      'Saturday plan: 10k easy pace from the north gate, 8:00. Walkers welcome, we loop back.', 'Marco Conti', now() - interval '1 day'
  where not exists (select 1 from public.group_messages m
      where m.group_id = g_walk and m.content like 'Saturday plan:%');

  insert into public.group_messages (group_id, user_id, content, author_name, created_at)
  select g_walk, u_elena,
      'I will join for the walking loop! Bringing the thermos.', 'Elena Moretti', now() - interval '20 hours'
  where not exists (select 1 from public.group_messages m
      where m.group_id = g_walk and m.content like 'I will join for the walking loop%');

  insert into public.group_messages (group_id, user_id, content, author_name, created_at)
  select g_morning, u_giulia,
      'Rainy morning here — did my check-ins with the window open anyway. Ten quiet minutes count double.', 'Giulia Ferrari', now() - interval '10 hours'
  where not exists (select 1 from public.group_messages m
      where m.group_id = g_morning and m.content like 'Rainy morning here%');

  -- ------------------------------------------ post con foto (media_paths)
  insert into public.space_posts (user_id, content, media_paths, created_at)
  select u_marco,
      'Morning run done. The park put on a show today.',
      array['https://picsum.photos/seed/cocoa-run/900/600'],
      now() - interval '30 hours'
  where not exists (select 1 from public.space_posts p
      where p.content like 'Morning run done. The park put on a show%');

  insert into public.space_posts (user_id, content, media_paths, created_at)
  select u_sofia,
      'Reset the desk, reset the mind. New notebook day.',
      array['https://picsum.photos/seed/cocoa-desk/900/600'],
      now() - interval '9 hours'
  where not exists (select 1 from public.space_posts p
      where p.content like 'Reset the desk, reset the mind%');

  -- foto su un post esistente (giornale nel parco di Luca)
  update public.space_posts
  set media_paths = array['https://picsum.photos/seed/cocoa-parkbench/900/600']
  where content like 'Tried journaling in the park today%'
    and coalesce(cardinality(media_paths), 0) = 0;

  -- commenti extra sulle foto
  insert into public.post_comments (post_id, user_id, content, author_name, created_at)
  select p.id, a.id, 'Okay the light in this one is unreal.', 'Sofia Rossi', now() - interval '26 hours'
  from public.space_posts p join auth.users a on a.email = 'sofia@dearcocoa.demo'
  where p.content like 'Morning run done%'
    and not exists (select 1 from public.post_comments c
        where c.post_id = p.id and c.content like 'Okay the light%');

  insert into public.post_comments (post_id, user_id, content, author_name, created_at)
  select p.id, a.id, 'New notebook day is a national holiday, honestly.', 'Giulia Ferrari', now() - interval '6 hours'
  from public.space_posts p join auth.users a on a.email = 'giulia@dearcocoa.demo'
  where p.content like 'Reset the desk%'
    and not exists (select 1 from public.post_comments c
        where c.post_id = p.id and c.content like 'New notebook day%');

  -- like sulle foto
  insert into public.post_likes (post_id, user_id)
  select p.id, a.id
  from (values
      ('Morning run done', 'sofia@dearcocoa.demo'),
      ('Morning run done', 'elena@dearcocoa.demo'),
      ('Morning run done', 'luca@dearcocoa.demo'),
      ('Reset the desk',   'elena@dearcocoa.demo'),
      ('Reset the desk',   'marco@dearcocoa.demo')
  ) as pairs(prefix, liker)
  join public.space_posts p on p.content like pairs.prefix || '%'
  join auth.users a on a.email = pairs.liker
  where not exists (
    select 1 from public.post_likes pl
    where pl.post_id = p.id and pl.user_id = a.id);

  update public.space_posts p set like_count = (
    select count(*) from public.post_likes pl where pl.post_id = p.id);

  raise notice 'Seed demo v3 completato: avatar, cover, evento fisico, gruppo extra, post con foto.';
end $$;
