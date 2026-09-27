-- Tests for supabase/migrations/*_initial_schema.sql. Run with: supabase test db
-- Everyone acts as the `authenticated` role with their own JWT, like the app.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-00000000000' || c)::uuid, c || '@test.dev'
from unnest(array['a', 'b', 'c', 'd', 'e', 'f']) c;

-- Codes and ids handed between the people below.
create temp table ids (who text primary key, family_id uuid, parent_code text, child_code text);
grant all on ids to authenticated;

create function pg_temp.act_as(who text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-00000000000' || who,
    'email', who || '@test.dev', 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

-- A (a child) starts a family for Mom and checks in once; B starts another.
select pg_temp.act_as('a');
insert into ids select 'a', id, parent_code, child_code from public.create_family(' Mom ', 'Sara');
insert into public.checkins (family_id, member_id, source)
  select family_id, id, 'tap' from public.members;
select pg_temp.act_as('b');
insert into ids select 'b', id, parent_code, child_code from public.create_family('Dad', 'Omar');

select ok((select bool_and(parent_code ~ '^[A-HJ-NP-Z2-9]{8}$' and child_code ~ '^[A-HJ-NP-Z2-9]{8}$'
                           and parent_code <> child_code) from ids),
          'codes are 8 characters without look-alikes');
select is((select parent_name from ids join public.families f on f.id = ids.family_id where who = 'b'),
          'Dad', 'create_family stores the parent''s name');

-- Isolation between families.
select is((select count(*) from public.families), 1::bigint, 'B sees only their own family');
select is((select count(*) from public.members), 1::bigint, 'B sees only their own members');
select is((select count(*) from public.checkins), 0::bigint, 'B cannot see A''s check-ins');
select throws_ok(
  $$ insert into public.schedules (family_id) select family_id from ids where who = 'a' $$,
  '42501', null, 'B cannot create A''s schedule');
select throws_ok(
  $$ update public.members set role = 'parent' $$,
  '42501', null, 'role is not client-editable');
select throws_ok(
  $$ select public.reinvite_parent((select family_id from ids where who = 'a')) $$,
  '42501', null, 'B cannot re-invite A''s parent');
select is((select count(*) from public.heartbeats), 0::bigint, 'clients cannot read heartbeats');

-- C, the parent, joins A's family with the parent code.
select pg_temp.act_as('c');
select is((select count(*) from public.families), 0::bigint, 'a user with no family sees nothing');
select is(public.join_family('NOPE2345', 'x'), null, 'a wrong code returns null');
select is(
  (select parent_code from public.join_family(
     (select lower(substr(parent_code, 1, 4) || ' - ' || substr(parent_code, 5)) from ids where who = 'a'),
     'ignored')),
  null, 'parent joins with the code, case, spaces and dashes ignored, and the code is used up');
select is((select display_name || '/' || role from public.members where user_id = auth.uid()),
          'Mom/parent', 'the parent takes the family''s parent_name');
select is((select count(*) from public.members), 2::bigint, 'the parent sees both A family members');
select is((select count(*) from public.checkins), 1::bigint, 'the parent sees A''s check-in');
select throws_ok(
  $$ insert into public.checkins (family_id, member_id, source)
     select family_id, id, 'tap' from public.members where display_name = 'Sara' $$,
  '42501', null, 'the parent cannot check in as someone else');

-- D, a sibling, joins with the child code; the used parent code is dead.
select pg_temp.act_as('d');
select is(public.join_family((select parent_code from ids where who = 'a'), 'Lina'), null,
          'a used parent code no longer works');
select is((select role from public.join_family((select child_code from ids where who = 'a'), 'Lina') f
           join public.members m on m.family_id = f.id and m.user_id = auth.uid()),
          'child', 'a sibling joins as a child with the child code');

-- Mom gets a new phone (E): D re-invites, E joins, the parent row moves.
update ids set parent_code = (select parent_code from public.reinvite_parent(family_id)) where who = 'a';
select pg_temp.act_as('e');
select isnt(public.join_family((select parent_code from ids where who = 'a'), 'x'), null,
            'the new phone joins with the fresh parent code');
select is((select count(*) || '/' || max(user_id::text) from public.members where role = 'parent'),
          '1/00000000-0000-0000-0000-00000000000e', 'still one parent, now on the new phone');
select is((select count(*) from public.checkins), 1::bigint, 'the check-in history stays with the parent');
select pg_temp.act_as('c');
select is((select count(*) from public.families), 0::bigint, 'the old phone loses access');

-- A child can be in two families.
select pg_temp.act_as('a');
select lives_ok($$ select public.join_family((select child_code from ids where who = 'b'), 'Sara') $$,
                'a child can join a second family');

-- F guesses codes: 10 wrong ones an hour, then blocked.
select pg_temp.act_as('f');
do $$ begin for i in 1..9 loop perform public.join_family('WRONG' || i, 'x'); end loop; end $$;
select is(public.join_family('WRONG10', 'x'), null, 'the 10th wrong code still answers');
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
