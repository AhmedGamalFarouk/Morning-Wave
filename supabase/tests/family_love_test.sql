-- Tests for supabase/migrations/*_family_love.sql. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

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

-- A is Mom's child, B is Mom; C has another family.
select pg_temp.act_as('a');
insert into ids select 'a', id, parent_code from public.create_family('Mom', 'Sara', 'Africa/Cairo');
select pg_temp.act_as('c');
insert into ids select 'c', id, parent_code from public.create_family('Dad', 'Omar', 'Europe/London');
select pg_temp.act_as('b', true);
select public.join_family((select parent_code from ids where who = 'a'), 'Mom');

select pg_temp.act_as('a');
select lives_ok(
  $$ insert into public.family_love (family_id, member_id)
     select family_id, id from public.members where user_id = auth.uid() $$,
  'a child sends love');

select pg_temp.act_as('b', true);
select is((select count(*) from public.family_love), 1::bigint,
          'the parent sees it');
select throws_ok(
  $$ insert into public.family_love (family_id, member_id)
     select family_id, id from public.members where user_id = auth.uid() $$,
  '42501', null, 'the parent cannot send love as themselves');

select pg_temp.act_as('c');
select is((select count(*) from public.family_love), 0::bigint,
          'another family sees none');
select throws_ok(
  $$ insert into public.family_love (family_id, member_id)
     select (select family_id from ids where who = 'a'), id
     from public.members where user_id = auth.uid() $$,
  '23503', null, 'a child of another family cannot send love into this one');
select throws_ok(
  $$ update public.family_love set created_at = now() $$,
  '42501', null, 'no one edits love once sent');

select * from finish();
rollback;
