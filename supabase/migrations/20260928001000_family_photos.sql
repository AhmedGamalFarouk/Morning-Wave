-- Family photos: a child sends a photo, the parent sees the latest one in
-- their photo frame. Paid extra (family_plan); the client enforces that,
-- since RevenueCat entitlements aren't synced to the database (see
-- lib/services/subscription.dart and the paywall, which already work the
-- same way).

-- Storage: one private bucket, one object per photo, path "{family_id}/{id}".
-- Capped at 5 MB (the client compresses well under that) and JPEG-only, so
-- one stray upload can't eat the $25 storage budget.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('family-photos', 'family-photos', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

create policy "members read their family's photos in storage"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'family-photos'
    and (storage.foldername(name))[1]::uuid in (select private.my_family_ids())
  );

-- Matches "a child sends a family photo" below: only a child of the family
-- named by the path's first folder can upload into it.
create policy "a child uploads a family photo"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'family-photos'
    and (storage.foldername(name))[1]::uuid in (
      select family_id from public.members
      where user_id = (select auth.uid()) and role = 'child'
    )
  );

-- The client keeps only the newest photo per family (see send() in
-- lib/family/photo_repository.dart), so a child can clear out older ones.
create policy "a child deletes a family photo"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'family-photos'
    and (storage.foldername(name))[1]::uuid in (
      select family_id from public.members
      where user_id = (select auth.uid()) and role = 'child'
    )
  );

-- One row per photo, newest last. storage_path points at the object above;
-- deleting the row does not delete the object (the Storage API does that).
create table public.family_photos (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null,
  member_id    uuid not null,
  storage_path text not null check (storage_path like family_id::text || '/%'),
  created_at   timestamptz not null default now(),
  foreign key (family_id, member_id) references public.members (family_id, id) on delete cascade
);

create index family_photos_family_created_idx on public.family_photos (family_id, created_at desc);

alter table public.family_photos enable row level security;

revoke select, insert, update, delete on public.family_photos from anon, authenticated;
grant select on public.family_photos to authenticated;
grant insert (family_id, member_id, storage_path) on public.family_photos to authenticated;
grant delete on public.family_photos to authenticated;

create policy "members read their family's photos"
  on public.family_photos for select to authenticated
  using (family_id in (select private.my_family_ids()));

-- Only a child sends a photo, same as who can pay for the family plan.
-- The composite FK ties member_id to family_id, so owning the child member
-- row is enough.
create policy "a child sends a family photo"
  on public.family_photos for insert to authenticated
  with check (member_id in (select id from public.members
                            where user_id = (select auth.uid()) and role = 'child'));

-- The client keeps only the newest photo per family, so a child can clear
-- out the older rows (any child, not just whoever sent them).
create policy "a child clears their family's older photos"
  on public.family_photos for delete to authenticated
  using (family_id in (
    select family_id from public.members
    where user_id = (select auth.uid()) and role = 'child'
  ));
