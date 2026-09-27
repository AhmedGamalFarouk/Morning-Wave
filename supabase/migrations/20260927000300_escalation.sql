-- Missed-morning escalation.
--
-- Every minute, pg_cron runs public.run_escalation(). It finds families whose
-- check-in window ended with no check-in (tap or steps) that local day and
-- inserts the alert rows that are due. The "Alert sender" Edge Function
-- delivers them; this migration only creates the rows.
--
--   step 1  window end + 15 min  push         to the parent (a gentle nudge)
--   step 2  window end + 30 min  urgent push  to the first child
--   step 3  window end + 45 min  push         to the second child, if there is one
--   step 4  window end + 45 min  email        to the children (recipient null)
--
-- The unique (family_id, day, step) rule on alerts makes each step fire at
-- most once per family per local day, however often the job runs.
--
-- Escalation stops as soon as the parent checks in, or someone acknowledges
-- any of that day's alerts (the app must set acknowledged_at only on a
-- deliberate tap, never when a notification is merely opened). If the job
-- was down, due steps are caught up for up to 12 hours after the window
-- closed. Families in away mode are skipped through the day the parent is
-- back (schedules.paused_until). Days are the family's own local days, so
-- time zones and daylight saving follow schedules.time_zone.

create or replace function public.escalate_missed_checkins(p_now timestamptz default now())
returns integer
language sql
set search_path = ''
as $$
  with children as (
    select family_id, id,
           row_number() over (partition by family_id order by created_at, id) as rank
    from public.members
    where role = 'child'
  ),
  known_zone_schedules as materialized (
    -- An unknown zone would make "at time zone" abort the run for every
    -- family, so drop it first, by the same rule the schema checks on write.
    -- Materialized, so the planner can't evaluate a zone before this filter.
    select * from public.schedules
    where private.is_known_zone(time_zone)
  ),
  days as (
    -- Look at yesterday too, so a window that ends late in the evening still
    -- escalates after local midnight.
    select s.family_id, s.time_zone, p.id as parent_id, p.created_at as parent_joined_at,
           d.day, (d.day + s.window_end) at time zone s.time_zone as window_closed_at
    from known_zone_schedules s
    -- The family's one parent. A new phone moves this same row to the new
    -- account, so the nudge and earlier check-ins follow the parent.
    join public.members p on p.family_id = s.family_id and p.role = 'parent'
    cross join lateral (
      values ((p_now at time zone s.time_zone)::date),
             ((p_now at time zone s.time_zone)::date - 1)
    ) as d(day)
    -- Away mode: paused_until falls on the day the parent is back, and
    -- mornings resume the day after, whatever time of that day it holds.
    where s.paused_until is null
       or d.day > (s.paused_until at time zone s.time_zone)::date
  ),
  missed as (
    select dy.*
    from days dy
    -- Catch up after an outage for up to 12 hours, then let the day go: an
    -- alert about yesterday morning would only confuse people.
    where p_now >= dy.window_closed_at
      and p_now < dy.window_closed_at + interval '12 hours'
      -- Nothing for a day that ended before the parent joined.
      and dy.parent_joined_at < dy.window_closed_at
      -- Only the parent's own check-in counts, from the start of that day up
      -- to now (a tap just after midnight still answers a late-evening
      -- window).
      and not exists (
        select 1 from public.checkins c
        where c.family_id = dy.family_id
          and c.member_id = dy.parent_id
          and c.created_at >= dy.day::timestamp at time zone dy.time_zone
          and c.created_at <= p_now)
      and not exists (
        select 1 from public.alerts a
        where a.family_id = dy.family_id and a.day = dy.day
          and a.acknowledged_at is not null)
  ),
  due as (
    select m.family_id, m.day, st.step, st.channel,
           case st.step
             when 1 then m.parent_id
             when 2 then (select id from children c where c.family_id = m.family_id and c.rank = 1)
             when 3 then (select id from children c where c.family_id = m.family_id and c.rank = 2)
           end as recipient_id
    from missed m
    cross join (values
      (1, interval '15 minutes', 'push'),
      (2, interval '30 minutes', 'urgent_push'),
      (3, interval '45 minutes', 'push'),
      (4, interval '45 minutes', 'email')
    ) as st(step, delay, channel)
    where m.window_closed_at + st.delay <= p_now
  ),
  inserted as (
    insert into public.alerts (family_id, day, step, channel, recipient_id)
    select family_id, day, step, channel, recipient_id
    from due
    where step = 4 or recipient_id is not null
    on conflict (family_id, day, step) do nothing
    returning 1
  )
  select count(*)::integer from inserted;
$$;

-- The job pg_cron runs. The heartbeat is written in the same transaction, so
-- a failing run leaves the heartbeat stale.
create or replace function public.run_escalation()
returns void
language sql
set search_path = ''
as $$
  select public.escalate_missed_checkins();
  insert into public.heartbeats (job, last_run_at)
  values ('escalation', now())
  on conflict (job) do update set last_run_at = excluded.last_run_at;
$$;

-- Server only: no API role may call these.
revoke all on function public.escalate_missed_checkins(timestamptz) from public, anon, authenticated;
revoke all on function public.run_escalation() from public, anon, authenticated;

select cron.schedule('escalation', '* * * * *', 'select public.run_escalation()');
