-- Tests for supabase/migrations/*_checkin_status.sql. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

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

-- Before any tap, nobody's checked in and nobody's away.
select pg_temp.act_as('a');
select is((select checked_in_today from public.family_status
           where family_id = (select family_id from ids where who = 'a')),
          false, 'not checked in before any tap');
select is((select away from public.family_status
           where family_id = (select family_id from ids where who = 'a')),
          false, 'not away by default');

-- B, the parent, says good morning.
select pg_temp.act_as('b', true);
select lives_ok(
  $$ insert into public.checkins (family_id, member_id, source)
     select family_id, id, 'tap' from public.members
     where user_id = auth.uid() and role = 'parent' $$,
  'the parent checks in');

-- A, the child, sees today's check-in.
select pg_temp.act_as('a');
select is((select checked_in_today from public.family_status
           where family_id = (select family_id from ids where who = 'a')),
          true, 'the child sees today’s check-in');
select isnt((select checked_in_at from public.family_status
             where family_id = (select family_id from ids where who = 'a')),
            null, 'a check-in time is recorded');

-- A sets the family away through tomorrow.
select lives_ok(
  $$ update public.schedules set paused_until = now() + interval '1 day'
     where family_id = (select family_id from ids where who = 'a') $$,
  'a child sets the family away');
select is((select away from public.family_status
           where family_id = (select family_id from ids where who = 'a')),
          true, 'the family shows as away');

-- C, in another family, sees none of A's status.
select pg_temp.act_as('c');
select is((select count(*) from public.family_status
           where family_id = (select family_id from ids where who = 'a')),
          0::bigint, 'a member of another family sees no status for it');

select * from finish();
rollback;
