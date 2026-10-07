-- "Send love": a child answers the parent's good morning with a heart, and
-- the parent's home shows who sent one. Only who and when; no text.
-- ponytail: no push yet, the parent sees it next time they open the app.
-- Add a gentle push through send-alerts if testers ask for it.

create table public.family_love (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null,
  member_id  uuid not null,
  created_at timestamptz not null default now(),
  foreign key (family_id, member_id) references public.members (family_id, id) on delete cascade
);

create index family_love_family_created_idx on public.family_love (family_id, created_at desc);

alter table public.family_love enable row level security;

revoke select, insert, update, delete on public.family_love from anon, authenticated;
grant select on public.family_love to authenticated;
grant insert (family_id, member_id) on public.family_love to authenticated;

create policy "members read their family's love"
  on public.family_love for select to authenticated
  using (family_id in (select private.my_family_ids()));

-- Only a child sends love, as their own member row; the composite FK ties
-- that row to family_id.
create policy "a child sends love"
  on public.family_love for insert to authenticated
  with check (member_id in (select id from public.members
                            where user_id = (select auth.uid()) and role = 'child'));
