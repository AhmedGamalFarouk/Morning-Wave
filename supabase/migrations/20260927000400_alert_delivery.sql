-- Alert delivery.
--
-- The escalation job inserts alert rows; the send-alerts Edge Function sends
-- them. Every 30 seconds pg_cron runs private.kick_alert_sender(), which
-- calls the function through pg_net, but only when some alert is ready.
--
-- The function never reads alerts directly. It calls claim_alerts(), which
-- leases the ready rows (FOR UPDATE SKIP LOCKED, so two overlapping calls
-- never get the same row), then finish_alert() for each one:
--   sent            -> sent_at is set, and the row is never picked up again
--   temporary error -> retried after 1, 2, 4, 8, 16, then every 30 minutes
--   permanent error -> failed_at is set, no more retries
-- A lease left by a call that died is picked up again after 2 minutes.
-- Temporary errors never give up on their own, so a long FCM or email outage
-- still ends in delivery. Only an alert still unsent 12 hours after that
-- morning's window closed is let go (failed_at, 'expired'), the same cutoff
-- the escalation job uses: news about yesterday morning would only confuse
-- people. A phone token FCM reports as gone is cleared from the member, so
-- later alerts don't keep trying it.
--
-- Health: the kick writes the 'send-alerts' heartbeat only while no alert has
-- been waiting for more than 10 minutes. A bad secret, a function that fails,
-- or an FCM or email outage all leave it stale, and the uptime check on
-- heartbeats notices.
--
-- Needs two Vault secrets (set once per project, never in git):
--   project_url            https://<ref>.supabase.co
--   alerts_webhook_secret  same value as the function's ALERTS_WEBHOOK_SECRET

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

alter table public.alerts
  add column attempts    integer not null default 0,
  add column claimed_at  timestamptz,
  add column retry_after timestamptz,
  add column failed_at   timestamptz,
  add column last_error  text check (char_length(last_error) <= 1000);

create index alerts_waiting_idx on public.alerts (created_at, step)
  where sent_at is null and failed_at is null;

-- When an alert stops being worth sending: 12 hours after that day's window
-- closed in the family's time zone.
create or replace function private.alert_deadline(p_family_id uuid, p_day date, p_created_at timestamptz)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select (p_day + s.window_end) at time zone s.time_zone
     from public.schedules s
     where s.family_id = p_family_id
       -- An unknown zone would abort the whole claim.
       and s.time_zone in (select name from pg_catalog.pg_timezone_names)),
    p_created_at) + interval '12 hours';
$$;

-- When that local day began for the family, or null if its zone is unknown.
create or replace function private.local_day_start(p_family_id uuid, p_day date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select p_day::timestamp at time zone s.time_zone
  from public.schedules s
  where s.family_id = p_family_id
    and s.time_zone in (select name from pg_catalog.pg_timezone_names);
$$;

-- Leases ready alerts and returns everything needed to send them, as a JSON
-- array (see Alert in supabase/functions/send-alerts/deliver.ts), oldest
-- first and in step order.
create or replace function public.claim_alerts(p_limit integer default 50)
returns jsonb
language sql
set search_path = ''
as $$
  with expired as (
    update public.alerts
    set failed_at = now(), last_error = 'expired'
    where sent_at is null and failed_at is null
      and private.alert_deadline(family_id, day, created_at) <= now()
  ),
  claimed as (
    update public.alerts a
    set claimed_at = now(), attempts = a.attempts + 1
    where a.id in (
      select id from public.alerts
      where sent_at is null and failed_at is null
        and (claimed_at is null or claimed_at < now() - interval '2 minutes')
        and (retry_after is null or retry_after <= now())
        and private.alert_deadline(family_id, day, created_at) > now()
      order by created_at, step
      limit p_limit
      for update skip locked)
    returning a.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'step', c.step,
    'channel', c.channel,
    -- What the family calls the parent ("Mom"), set by the child at sign-up.
    'parent_name', f.parent_name,
    'fcm_token', r.fcm_token,
    'emails', case when c.channel = 'email' then coalesce(
      (select jsonb_agg(jsonb_build_object('email', m.email, 'name', m.display_name)
                        order by m.created_at, m.id)
       from public.members m
       where m.family_id = c.family_id and m.role = 'child' and m.email is not null),
      '[]'::jsonb) else '[]'::jsonb end,
    -- The escalation job's rule: once the parent has checked in herself that
    -- day, or someone has acknowledged it, nothing more goes out.
    'checked_in', exists (
        select 1 from public.checkins k
        join public.members p on p.id = k.member_id and p.role = 'parent'
        where k.family_id = c.family_id
          and k.created_at >= private.local_day_start(c.family_id, c.day)
          and k.created_at <= now())
      or exists (
        select 1 from public.alerts o
        where o.family_id = c.family_id and o.day = c.day
          and o.acknowledged_at is not null)
  ) order by c.created_at, c.step), '[]'::jsonb)
  from claimed c
  join public.families f on f.id = c.family_id
  left join public.members r on r.id = c.recipient_id;
$$;

create or replace function public.finish_alert(
  p_id uuid,
  p_error text,
  p_permanent boolean default false,
  p_dead_token text default null)
returns void
language sql
set search_path = ''
as $$
  update public.alerts
  set sent_at     = case when p_error is null then now() end,
      last_error  = left(p_error, 1000),
      claimed_at  = case when p_error is null then claimed_at end,
      failed_at   = case when p_error is not null and p_permanent then now() end,
      retry_after = case when p_error is not null and not p_permanent
                         then now() + least(interval '1 minute' * 2 ^ least(attempts - 1, 5),
                                            interval '30 minutes') end
  where id = p_id and sent_at is null;

  -- Only if it's still the token that failed, not one the phone just renewed.
  update public.members m
  set fcm_token = null
  from public.alerts a
  where a.id = p_id and m.id = a.recipient_id and m.fcm_token = p_dead_token;
$$;

-- Writes the health heartbeat, and calls the Edge Function when there's
-- something to send.
create or replace function private.kick_alert_sender()
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  insert into public.heartbeats (job, last_run_at)
  select 'send-alerts', now()
  where not exists (select 1 from public.alerts
                    where sent_at is null and failed_at is null
                      and created_at < now() - interval '10 minutes')
  on conflict (job) do update set last_run_at = excluded.last_run_at;

  if not exists (select 1 from public.alerts
                 where sent_at is null and failed_at is null
                   and (retry_after is null or retry_after <= now())) then
    return;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'alerts_webhook_secret';
  if v_url is null or v_secret is null then
    raise warning 'send-alerts: Vault secrets project_url and alerts_webhook_secret are not set';
    return;
  end if;
  perform net.http_post(
    url := v_url || '/functions/v1/send-alerts',
    headers := jsonb_build_object('content-type', 'application/json', 'x-alerts-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000);
end;
$$;

-- Server only: no API role may call these. The Edge Function uses the
-- service role, which also needs the private schema for the two helpers.
revoke all on function private.alert_deadline(uuid, date, timestamptz) from public, anon, authenticated;
revoke all on function private.local_day_start(uuid, date) from public, anon, authenticated;
revoke all on function public.claim_alerts(integer) from public, anon, authenticated;
revoke all on function public.finish_alert(uuid, text, boolean, text) from public, anon, authenticated;
revoke all on function private.kick_alert_sender() from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.alert_deadline(uuid, date, timestamptz) to service_role;
grant execute on function private.local_day_start(uuid, date) to service_role;
grant execute on function public.claim_alerts(integer) to service_role;
grant execute on function public.finish_alert(uuid, text, boolean, text) to service_role;

select cron.schedule('send-alerts', '30 seconds', 'select private.kick_alert_sender()');
