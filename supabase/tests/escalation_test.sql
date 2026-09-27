-- Tests for the missed-morning escalation (supabase/migrations/*_escalation.sql).
-- Run with `supabase test db`, or `pg_prove` against any database with the
-- migrations applied. Every case passes an explicit "now" to the function.

begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

-- A family with a parent who joined long ago, n children and a schedule.
create function pg_temp.member(f uuid, role text, joined timestamptz) returns uuid
language sql as $$
  with u as (insert into auth.users (id) values (gen_random_uuid()) returning id)
  insert into public.members (family_id, user_id, role, display_name, created_at)
  select f, u.id, role, role, joined from u
  returning id;
$$;

create function pg_temp.family(tz text, window_end time, n_children int default 2,
                               paused_until timestamptz default null,
                               parent_joined timestamptz default '2026-01-01Z')
returns uuid language plpgsql as $$
declare f uuid;
begin
  insert into public.families (parent_name) values ('Mom') returning id into f;
  perform pg_temp.member(f, 'parent', parent_joined);
  for i in 1..n_children loop
    perform pg_temp.member(f, 'child', '2026-01-01Z'::timestamptz + i * interval '1 minute');
  end loop;
  insert into public.schedules (family_id, window_start, window_end, time_zone, paused_until)
  values (f, window_end - interval '2 hours', window_end, tz, paused_until);
  return f;
end $$;

create function pg_temp.checkin(f uuid, at timestamptz, src text default 'tap')
returns void language sql as $$
  insert into public.checkins (family_id, member_id, source, created_at)
  select f, id, src, at from public.members where family_id = f and role = 'parent';
$$;

create function pg_temp.run(at timestamptz) returns int language sql as $$
  select public.escalate_missed_checkins(at);
$$;

create function pg_temp.steps(f uuid) returns int[] language sql as $$
  select coalesce(array_agg(step order by step), '{}') from public.alerts where family_id = f;
$$;

-- Keep each case to its own family: delete everyone else's schedule first.
create function pg_temp.only(f uuid) returns void language sql as $$
  delete from public.schedules where family_id <> f;
$$;

-- 1. Missed morning in New York (EDT, window ends 09:00 = 13:00Z):
--    each step fires once, in order, at +15, +30 and +45.
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;

select is(pg_temp.run('2026-10-05 13:14Z'), 0, 'nothing before +15 min');
select is(pg_temp.run('2026-10-05 13:15Z'), 1, 'nudge at +15 min');
select is(pg_temp.run('2026-10-05 13:16Z'), 0, 'nudge only once');
select is(pg_temp.run('2026-10-05 13:30Z'), 1, 'urgent push at +30 min');
select is(pg_temp.run('2026-10-05 13:45Z'), 2, 'second contact and email at +45 min');
select is(pg_temp.run('2026-10-05 20:00Z'), 0, 'nothing more later that day');
select is(pg_temp.steps(id), '{1,2,3,4}', 'steps 1 to 4, in order, once each') from fam;
select results_eq(
  $$ select step, channel, m.role
     from public.alerts a left join public.members m on m.id = a.recipient_id
     where a.family_id = (select id from fam) order by step $$,
  $$ values (1::smallint, 'push', 'parent'), (2::smallint, 'urgent_push', 'child'),
            (3::smallint, 'push', 'child'), (4::smallint, 'email', null) $$,
  'right channel and recipient for each step');
select is(
  (select array_agg(m.created_at order by a.step) from public.alerts a
   join public.members m on m.id = a.recipient_id
   where a.family_id = (select id from fam) and a.step in (2, 3)),
  array['2026-01-01 00:01Z', '2026-01-01 00:02Z']::timestamptz[],
  'first child gets step 2, second child gets step 3');
select is((select array_agg(distinct day) from public.alerts a join fam on a.family_id = fam.id),
          array['2026-10-05'::date], 'alerts are dated the family''s local day');
select is(pg_temp.run('2026-10-06 13:15Z'), 1, 'a new day starts a new escalation');
drop table fam;

-- 2. A tap on time sends nothing.
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select pg_temp.checkin(id, '2026-10-05 12:10Z') from fam;
select is(pg_temp.run('2026-10-05 14:00Z'), 0, 'on-time tap: nothing sent');
drop table fam;

-- 3. Steps count as a check-in, even before the window opens.
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select pg_temp.checkin(id, '2026-10-05 08:00Z', 'steps') from fam;
select is(pg_temp.run('2026-10-05 14:00Z'), 0, 'steps at 4am local: nothing sent');
select is(pg_temp.run('2026-10-06 13:15Z'), 1, 'yesterday''s steps don''t cover today');
drop table fam;

-- 4. A late tap stops the escalation where it is.
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select pg_temp.run('2026-10-05 13:15Z');
select pg_temp.checkin(id, '2026-10-05 13:20Z') from fam;
select is(pg_temp.run('2026-10-05 14:00Z'), 0, 'late tap: no further steps');
select is(pg_temp.steps(id), '{1}', 'only the nudge went out') from fam;
drop table fam;

-- 5. An acknowledged alert stops the escalation.
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select pg_temp.run('2026-10-05 13:30Z');
update public.alerts set acknowledged_at = '2026-10-05 13:31Z' where family_id = (select id from fam);
select is(pg_temp.run('2026-10-05 14:00Z'), 0, 'acknowledged: no further steps');
drop table fam;

-- 6. Away mode sends nothing through the day she's back, then resumes.
create temp table fam as
  select pg_temp.family('America/New_York', '09:00',
                        paused_until => '2026-10-07 18:00-04') as id;
select pg_temp.only(id) from fam;
select is(pg_temp.run('2026-10-05 14:00Z'), 0, 'away: nothing sent');
select is(pg_temp.run('2026-10-07 14:00Z'), 0, 'away, the day she''s back: nothing sent');
select is(pg_temp.run('2026-10-08 13:15Z'), 1, 'morning after she''s back: escalation resumes');
drop table fam;

-- 7. Daylight saving. New York springs forward on 14 Mar 2027:
--    09:00 is now 13:00Z (it was 14:00Z the day before).
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select pg_temp.checkin(id, '2027-03-13 13:00Z') from fam;
select is(pg_temp.run('2027-03-14 13:14Z'), 0, 'spring forward: nothing before 09:15 EDT');
select is(pg_temp.run('2027-03-14 13:15Z'), 1, 'spring forward: nudge at 09:15 EDT');
drop table fam;

--    Falls back on 1 Nov 2026: 09:00 is now 14:00Z (it was 13:00Z).
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select pg_temp.checkin(id, '2026-10-31 12:00Z') from fam;
select is(pg_temp.run('2026-11-01 13:30Z'), 0, 'fall back: nothing at 08:30 EST');
select is(pg_temp.run('2026-11-01 14:15Z'), 1, 'fall back: nudge at 09:15 EST');
drop table fam;

-- 8. The local day decides which check-in counts (Tokyo, UTC+9):
--    a tap at 23:30Z on the 4th is 08:30 on the 5th in Tokyo.
create temp table fam as select pg_temp.family('Asia/Tokyo', '09:00') as id;
select pg_temp.only(id) from fam;
select pg_temp.checkin(id, '2026-10-04 23:30Z') from fam;
select is(pg_temp.run('2026-10-05 01:00Z'), 0, 'Tokyo: morning tap counts for the local day');
drop table fam;

-- 9. A late-evening window still escalates after local midnight.
create temp table fam as select pg_temp.family('America/New_York', '23:50') as id;
select pg_temp.only(id) from fam;
select is(pg_temp.run('2026-10-06 04:35Z'), 4, 'window ending 23:50: all four steps by 00:35');
select is((select distinct day from public.alerts a join fam on a.family_id = fam.id),
          '2026-10-05'::date, 'dated the day the window was in');
drop table fam;

-- 10. One child: no second-contact push, but the email still goes.
create temp table fam as select pg_temp.family('America/New_York', '09:00', n_children => 1) as id;
select pg_temp.only(id) from fam;
select pg_temp.run('2026-10-05 13:45Z');
select is(pg_temp.steps(id), '{1,2,4}', 'one child: steps 1, 2 and 4') from fam;
drop table fam;

-- 11. No alert for a morning that ended before the parent joined.
create temp table fam as
  select pg_temp.family('America/New_York', '09:00', parent_joined => '2026-10-05 15:00Z') as id;
select pg_temp.only(id) from fam;
select is(pg_temp.run('2026-10-05 16:00Z'), 0, 'setup day: nothing sent');
drop table fam;

-- 12. A new phone moves the parent's row to her new account (join_family),
--     so the nudge goes to the same member row.
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000aa');
update public.members set user_id = '00000000-0000-0000-0000-0000000000aa', fcm_token = null
where family_id = (select id from fam) and role = 'parent';
select pg_temp.run('2026-10-05 13:15Z');
select is((select m.user_id from public.alerts a join public.members m on m.id = a.recipient_id
           where a.family_id = (select id from fam) and a.step = 1),
          '00000000-0000-0000-0000-0000000000aa'::uuid, 'new phone: the nudge goes to her new account');
drop table fam;

-- 13. After an outage, due steps catch up in order, but only for 12 hours.
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select is(pg_temp.run('2026-10-05 13:50Z'), 4, 'outage: all due steps at once');
select is(pg_temp.steps(id), '{1,2,3,4}', 'outage: still in order') from fam;
drop table fam;
create temp table fam as select pg_temp.family('America/New_York', '09:00') as id;
select pg_temp.only(id) from fam;
select is(pg_temp.run('2026-10-06 01:30Z'), 0, 'outage over 12 hours: that morning is let go');
drop table fam;

-- 14. The job itself: heartbeat written, scheduled every minute.
select public.run_escalation();
select ok((select last_run_at = now() from public.heartbeats where job = 'escalation'),
          'run_escalation writes the heartbeat');
select is((select schedule from cron.job where jobname = 'escalation'), '* * * * *',
          'pg_cron runs it every minute');

select * from finish();
rollback;
