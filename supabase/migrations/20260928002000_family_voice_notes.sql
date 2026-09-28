-- Family voice notes: a child records a short hello, the parent plays back
-- the latest one. Paid extra (family_plan), same client-side gate as photos
-- (see lib/services/subscription.dart) since RevenueCat entitlements aren't
-- synced to the database.

-- Storage: one private bucket, one object per note, path "{family_id}/{id}".
-- The client records AAC at a low bitrate and caps it around 60s, so 2 MB
-- comfortably covers it without letting one stray recording eat the budget.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('family-voice-notes', 'family-voice-notes', false, 2097152, array['audio/aac'])
on conflict (id) do nothing;

create policy "members read their family's voice notes in storage"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'family-voice-notes'
    and (storage.foldername(name))[1]::uuid in (select private.my_family_ids())
  );

-- Matches "a child sends a family voice note" below: only a child of the
-- family named by the path's first folder can upload into it.
create policy "a child uploads a family voice note"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'family-voice-notes'
    and (storage.foldername(name))[1]::uuid in (
      select family_id from public.members
      where user_id = (select auth.uid()) and role = 'child'
    )
  );

-- The client keeps only the newest voice note per family (see send() in
-- lib/family/voice_note_repository.dart), so a child can clear out older
-- ones.
create policy "a child deletes a family voice note"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'family-voice-notes'
    and (storage.foldername(name))[1]::uuid in (
      select family_id from public.members
      where user_id = (select auth.uid()) and role = 'child'
    )
  );

-- One row per voice note, newest last. storage_path points at the object
-- above; deleting the row does not delete the object (the Storage API does).
create table public.family_voice_notes (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null,
  member_id    uuid not null,
  storage_path text not null check (storage_path like family_id::text || '/%'),
  created_at   timestamptz not null default now(),
  foreign key (family_id, member_id) references public.members (family_id, id) on delete cascade
);

create index family_voice_notes_family_created_idx
  on public.family_voice_notes (family_id, created_at desc);

alter table public.family_voice_notes enable row level security;

revoke select, insert, update, delete on public.family_voice_notes from anon, authenticated;
grant select on public.family_voice_notes to authenticated;
grant insert (family_id, member_id, storage_path) on public.family_voice_notes to authenticated;
grant delete on public.family_voice_notes to authenticated;

create policy "members read their family's voice notes"
  on public.family_voice_notes for select to authenticated
  using (family_id in (select private.my_family_ids()));

-- Only a child sends a voice note, same as who can pay for the family plan.
-- The composite FK ties member_id to family_id, so owning the child member
-- row is enough.
create policy "a child sends a family voice note"
  on public.family_voice_notes for insert to authenticated
  with check (member_id in (select id from public.members
                            where user_id = (select auth.uid()) and role = 'child'));

-- The client keeps only the newest voice note per family, so a child can
-- clear out the older rows (any child, not just whoever sent them).
create policy "a child clears their family's older voice notes"
  on public.family_voice_notes for delete to authenticated
  using (family_id in (
    select family_id from public.members
    where user_id = (select auth.uid()) and role = 'child'
  ));
