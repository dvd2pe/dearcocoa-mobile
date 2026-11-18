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
