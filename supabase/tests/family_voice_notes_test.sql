-- Tests for supabase/migrations/*_family_voice_notes.sql. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000000' || c)::uuid, c || '@test.dev'
from unnest(array['a', 'b', 'c']) c;

create temp table ids (who text primary key, family_id uuid, parent_code text);
grant all on ids to authenticated;

create function pg_temp.act_as(who text, anonymous boolean default false) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-00000000000' || who,
    'role', 'authenticated', 'is_anonymous', anonymous)::text, true);
$$;

set local role authenticated;

-- A starts a family and is its child; C starts an unrelated family.
select pg_temp.act_as('a');
insert into ids select 'a', id, parent_code from public.create_family('Mom', 'Sara', 'Africa/Cairo');
select pg_temp.act_as('c');
insert into ids select 'c', id, parent_code from public.create_family('Dad', 'Omar', 'Europe/London');

-- B, the parent, joins A's family.
select pg_temp.act_as('b', true);
select public.join_family((select parent_code from ids where who = 'a'), 'Mom');

-- A, the child, sends a voice note.
select pg_temp.act_as('a');
select lives_ok(
  $$ insert into public.family_voice_notes (family_id, member_id, storage_path)
     select family_id, id, family_id || '/1.aac' from public.members
     where user_id = auth.uid() and role = 'child' $$,
  'a child sends a family voice note');
select is((select count(*) from public.family_voice_notes), 1::bigint,
          'the voice note is recorded');
select throws_ok(
  $$ insert into public.family_voice_notes (family_id, member_id, storage_path)
     select family_id, id, family_id || '/2.aac' from public.members
     where role = 'parent' $$,
  '42501', null, 'the parent cannot send a family voice note');
select throws_ok(
  $$ insert into public.family_voice_notes (family_id, member_id, storage_path)
     select family_id, id, '00000000-0000-0000-0000-000000000000/3.aac' from public.members
     where user_id = auth.uid() and role = 'child' $$,
  '23514', null, 'a voice note path must sit under its own family_id');

-- B, the parent, reads the family's voice notes but cannot delete one.
select pg_temp.act_as('b', true);
select is((select count(*) from public.family_voice_notes), 1::bigint,
          'the parent reads the family''s voice notes');
select is_empty(
  $$ delete from public.family_voice_notes returning 1 $$,
  'the parent cannot delete a family voice note');

-- C, in another family, sees none of it and cannot touch it either.
select pg_temp.act_as('c');
select is((select count(*) from public.family_voice_notes), 0::bigint,
          'a member of another family sees no voice notes');
select throws_ok(
  $$ insert into public.family_voice_notes (family_id, member_id, storage_path)
     select (select family_id from ids where who = 'a'), id, (select family_id from ids where who = 'a') || '/4.aac'
     from public.members where user_id = auth.uid() and role = 'child' $$,
  '23503', null, 'a child of another family cannot send into this one'
    || ' (member_id and family_id must belong to the same family)');
select is_empty(
  $$ delete from public.family_voice_notes returning 1 $$,
  'a child of another family cannot delete this family''s voice note');
select throws_ok(
  $$ update public.family_voice_notes set storage_path = 'x' $$,
  '42501', null, 'no one can edit a voice note row once sent');

-- A, the child, clears the family's older voice note (what send() does
-- before inserting the next one).
select pg_temp.act_as('a');
select lives_ok(
  $$ delete from public.family_voice_notes $$,
  'a child clears their family''s older voice note');
select is((select count(*) from public.family_voice_notes), 0::bigint,
          'the voice note is gone');

select * from finish();
rollback;
