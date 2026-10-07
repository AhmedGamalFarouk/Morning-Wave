-- Tests for supabase/migrations/*_delete_account.sql. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000000' || c)::uuid, c || '@test.dev'
from unnest(array['a', 'b', 'c', 'd']) c;

create temp table ids (who text primary key, family_id uuid, parent_code text, child_code text);
grant all on ids to authenticated;

create function pg_temp.act_as(who text, anonymous boolean default false) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-00000000000' || who,
    'role', 'authenticated', 'is_anonymous', anonymous)::text, true);
$$;

set local role authenticated;

-- A starts Mom's family; B is Mom; D is A's brother. C has another family.
select pg_temp.act_as('a');
insert into ids select 'a', id, parent_code, child_code from public.create_family('Mom', 'Sara', 'Africa/Cairo');
select pg_temp.act_as('c');
insert into ids select 'c', id, parent_code, child_code from public.create_family('Dad', 'Omar', 'Europe/London');
select pg_temp.act_as('b', true);
select public.join_family((select parent_code from ids where who = 'a'), 'Mom');
select pg_temp.act_as('d');
select public.join_family((select child_code from ids where who = 'a'), 'Ali');

-- A sends a photo, D a voice note, C a photo in his own family.
select pg_temp.act_as('a');
insert into public.family_photos (family_id, member_id, storage_path)
  select family_id, id, family_id || '/a.jpg' from public.members where user_id = auth.uid();
select pg_temp.act_as('d');
insert into public.family_voice_notes (family_id, member_id, storage_path)
  select family_id, id, family_id || '/d.m4a' from public.members where user_id = auth.uid();
select pg_temp.act_as('c');
insert into public.family_photos (family_id, member_id, storage_path)
  select family_id, id, family_id || '/c.jpg' from public.members where user_id = auth.uid();

-- A leaves while D stays: only A's own files go, the family stays.
select pg_temp.act_as('a');
select results_eq(
  $$ select bucket, path from public.my_account_files() $$,
  $$ values ('family-photos', (select family_id from ids where who = 'a') || '/a.jpg') $$,
  'a child who is not the last one removes only what they sent');
select lives_ok($$ select public.delete_my_account() $$, 'a child deletes their account');

reset role;
select is((select count(*) from auth.users where email = 'a@test.dev'), 0::bigint,
          'the account is gone');
select is((select count(*) from public.members m join ids on m.family_id = ids.family_id
           where ids.who = 'a'), 2::bigint,
          'the family keeps its parent and other child');
select is((select count(*) from public.family_photos p join ids on p.family_id = ids.family_id
           where ids.who = 'a'), 0::bigint,
          'their photo rows go with them');
set local role authenticated;

-- D, now the last child, takes the whole family with him.
select pg_temp.act_as('d');
select results_eq(
  $$ select bucket, path from public.my_account_files() $$,
  $$ values ('family-voice-notes', (select family_id from ids where who = 'a') || '/d.m4a') $$,
  'the last child removes every file of the family');
select public.delete_my_account();

reset role;
select is((select count(*) from public.families where id = (select family_id from ids where who = 'a')),
          0::bigint, 'a family with no child left goes too');
select is((select count(*) from public.schedules where family_id = (select family_id from ids where who = 'a')),
          0::bigint, 'with its schedule');
select is((select count(*) from public.family_photos p join ids on p.family_id = ids.family_id
           where ids.who = 'c'), 1::bigint,
          'another family is untouched');

set local role anon;
select throws_ok($$ select public.delete_my_account() $$, '42501', null,
                 'signed-out callers cannot call it');

select * from finish();
rollback;
