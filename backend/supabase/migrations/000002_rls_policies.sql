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
