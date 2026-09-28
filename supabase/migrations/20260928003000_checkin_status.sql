-- The parent's tap and the child's home screen both need one thing: has the
-- parent said good morning today, in the family's own day (see
-- private.is_known_zone and the escalation job, which counts days the same
-- way), and are they away. A security-invoker view keeps that logic in one
-- place instead of duplicating it on the client, while still going through
-- the same RLS as querying schedules and checkins directly.

create view public.family_status
with (security_invoker = true) as
select
  s.family_id,
  s.window_end as usual_by,
  exists (
    select 1 from public.checkins c
    where c.family_id = s.family_id
      and c.source = 'tap'
      and (c.created_at at time zone s.time_zone)::date
        = (now() at time zone s.time_zone)::date
  ) as checked_in_today,
  (
    select max(c.created_at) from public.checkins c
    where c.family_id = s.family_id
      and c.source = 'tap'
      and (c.created_at at time zone s.time_zone)::date
        = (now() at time zone s.time_zone)::date
  ) as checked_in_at,
  s.paused_until is not null
    and (now() at time zone s.time_zone)::date
      <= (s.paused_until at time zone s.time_zone)::date
    as away,
  case when s.paused_until is not null
    then (s.paused_until at time zone s.time_zone)::date
  end as away_until
from public.schedules s;

grant select on public.family_status to authenticated;
