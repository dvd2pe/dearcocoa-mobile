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
