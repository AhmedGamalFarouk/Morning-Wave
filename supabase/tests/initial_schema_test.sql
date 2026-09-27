-- Tests for supabase/migrations/*_initial_schema.sql. Run with: supabase test db
-- Everyone acts as the `authenticated` role with their own JWT, like the app.
-- Children have real accounts; parents sign in anonymously.
begin;
create extension if not exists pgtap with schema extensions;
select plan(38);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000000' || c)::uuid, c || '@test.dev'
from unnest(array['a', 'b', 'c', 'd', 'e', 'f', '7']) c;

-- Codes and ids handed between the people below.
create temp table ids (who text primary key, family_id uuid, parent_code text, child_code text);
grant all on ids to authenticated;

create function pg_temp.act_as(who text, anonymous boolean default false) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-00000000000' || who,
    'role', 'authenticated', 'is_anonymous', anonymous)::text, true);
$$;

set local role authenticated;

-- A starts a family for Mom, B one for Dad.
select pg_temp.act_as('a');
insert into ids select 'a', id, parent_code, child_code from public.create_family(' Mom ', 'Sara', 'Africa/Cairo');
select pg_temp.act_as('b');
insert into ids select 'b', id, parent_code, child_code from public.create_family('Dad', 'Omar', 'Europe/London');

select pg_temp.act_as('a');
select ok((select bool_and(parent_code ~ '^[A-HJ-NP-Z2-9]{8}$' and child_code ~ '^[A-HJ-NP-Z2-9]{8}$'
                           and parent_code <> child_code) from ids),
          'codes are 8 characters without look-alikes');
select is((select parent_name from public.families), 'Mom', 'create_family stores the trimmed parent name');
select is((select time_zone from public.schedules), 'Africa/Cairo', 'create_family makes the schedule');
select throws_ok($$ select public.create_family('Mom', 'Sara', 'PST') $$,
                 '23514', null, 'abbreviations are not time zones');
select throws_ok($$ select public.create_family('Mom', 'Sara', '+03') $$,
                 '23514', null, 'offsets are not time zones');
select throws_ok($$ update public.schedules set paused_until = now() + interval '400 days' $$,
                 '23514', null, 'away mode is capped at a year');
select throws_ok($$ update public.schedules set family_id = (select family_id from ids where who = 'b') $$,
                 '42501', null, 'a schedule cannot move to another family');
select throws_ok(
  $$ insert into public.checkins (family_id, member_id, source)
     select family_id, id, 'tap' from public.members $$,
  '42501', null, 'a child cannot check in');
select throws_ok(
  $$ select public.join_family((select parent_code from ids where who = 'a'), 'x') $$,
  '42501', null, 'a signed-in child cannot use up the parent code');

-- C, the parent, signs in anonymously and joins with the parent code.
select pg_temp.act_as('c', true);
select throws_ok($$ select public.create_family('Mom', 'x', 'UTC') $$,
                 '42501', null, 'anonymous users cannot start a family');
select is((select count(*) from public.join_family('NOPE2345', 'x')), 0::bigint,
          'a wrong code returns no rows');
select is(
  (select count(*) from public.join_family(
     (select lower(substr(parent_code, 1, 4) || ' - ' || substr(parent_code, 5)) from ids where who = 'a'),
     'ignored') where parent_code is null),
  1::bigint, 'the parent joins, case, spaces and dashes ignored, and the code is used up');
select is((select display_name || '/' || role from public.members where user_id = auth.uid()),
          'Mom/parent', 'the parent takes the family''s parent_name');

insert into public.checkins (family_id, member_id, source)
  select family_id, id, 'tap' from public.members where user_id = auth.uid();
select throws_ok(
  $$ insert into public.checkins (family_id, member_id, source, created_at)
     select family_id, id, 'tap', now() + interval '1 day' from public.members where user_id = auth.uid() $$,
  '42501', null, 'check-in time is set by the server');
select throws_ok(
  $$ insert into public.checkins (family_id, member_id, source)
     select family_id, id, 'tap' from public.members where display_name = 'Sara' $$,
  '42501', null, 'the parent cannot check in as someone else');
select is((select count(*) from public.members), 2::bigint, 'the parent sees both A family members');
select throws_ok($$ select fcm_token from public.members $$,
                 '42501', null, 'push tokens are not readable');

-- B is in another family and sees none of A's.
select pg_temp.act_as('b');
select is((select count(*) from public.families), 1::bigint, 'B sees only their own family');
select is((select count(*) from public.members), 1::bigint, 'B sees only their own members');
select is((select count(*) from public.checkins), 0::bigint, 'B cannot see A''s check-ins');
select is_empty(
  $$ update public.schedules set window_end = '11:00'
     where family_id = (select family_id from ids where who = 'a') returning 1 $$,
  'B cannot change A''s schedule');
select throws_ok($$ update public.members set role = 'parent' $$,
                 '42501', null, 'role is not client-editable');
select throws_ok($$ select public.reinvite_parent((select family_id from ids where who = 'a')) $$,
                 '42501', null, 'B cannot re-invite A''s parent');
select is((select count(*) from public.heartbeats), 0::bigint, 'clients cannot read heartbeats');
select throws_ok($$ update public.alerts set sent_at = now() $$,
                 '42501', null, 'alert delivery columns are not client-editable');

-- D, a sibling, joins with the child code; the used parent code is dead.
select pg_temp.act_as('d');
select is((select count(*) from public.join_family((select parent_code from ids where who = 'a'), 'Lina')),
          0::bigint, 'a used parent code no longer works');
select public.join_family((select child_code from ids where who = 'a'), 'Lina');
select is((select role from public.members where user_id = auth.uid()),
          'child', 'a sibling joins as a child with the child code');
select pg_temp.act_as('7', true);
select throws_ok($$ select public.join_family((select child_code from ids where who = 'a'), 'x') $$,
                 '42501', null, 'anonymous users cannot use the child code');

-- Mom gets a new phone (E): D re-invites, E joins, the parent row moves.
select pg_temp.act_as('d');
update ids set parent_code = (select parent_code from public.reinvite_parent(family_id)) where who = 'a';
select pg_temp.act_as('e', true);
select is((select count(*) from public.join_family((select parent_code from ids where who = 'a'), 'x')),
          1::bigint, 'the new phone joins with the fresh parent code');
select is((select count(*) || '/' || max(user_id::text) from public.members where role = 'parent'),
          '1/00000000-0000-0000-0000-00000000000e', 'still one parent, now on the new phone');
select is((select count(*) from public.checkins), 1::bigint, 'the check-in history stays with the parent');
select pg_temp.act_as('c', true);
select is((select count(*) from public.families), 0::bigint, 'the old phone loses access');

-- D replaces the sibling code; the old one stops working.
select pg_temp.act_as('d');
select isnt((select child_code from public.rotate_child_code((select family_id from ids where who = 'a'))),
            (select child_code from ids where who = 'a'), 'a child can replace the sibling code');
select pg_temp.act_as('7');
select is((select count(*) from public.join_family((select child_code from ids where who = 'a'), 'x')),
          0::bigint, 'the old sibling code no longer works');

-- A child can be in two families.
select pg_temp.act_as('a');
select lives_ok($$ select public.join_family((select child_code from ids where who = 'b'), 'Sara') $$,
                'a child can join a second family');

-- F guesses codes: 10 wrong ones an hour, then blocked.
select pg_temp.act_as('f', true);
do $$ begin for i in 1..9 loop perform public.join_family('WRONG' || i, 'x'); end loop; end $$;
select is((select count(*) from public.join_family('WRONG10', 'x')), 0::bigint,
          'the 10th wrong code still answers');
select throws_ok($$ select public.join_family('WRONG11', 'x') $$,
                 'PT429', null, 'the 11th attempt in an hour is refused');

reset role;

insert into public.alerts (family_id, day, step, channel)
  select family_id, '2026-09-27', 1, 'push' from ids where who = 'a';
select throws_ok(
  $$ insert into public.alerts (family_id, day, step, channel)
     select family_id, '2026-09-27', 1, 'push' from ids where who = 'a' $$,
  '23505', null, 'the same alert step cannot fire twice on one day');

select * from finish();
rollback;
