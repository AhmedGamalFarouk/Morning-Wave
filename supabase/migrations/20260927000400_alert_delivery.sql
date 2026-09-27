-- Alert delivery.
--
-- The escalation job inserts alert rows; the send-alerts Edge Function sends
-- them. Every 30 seconds pg_cron runs private.kick_alert_sender(), which
-- calls the function through pg_net, but only when some alert is waiting.
--
-- The function never reads alerts directly. It calls claim_alerts(), which
-- leases the waiting rows (FOR UPDATE SKIP LOCKED, so two overlapping calls
-- never get the same row), then finish_alert() for each one:
--   sent            -> sent_at is set, and the row is never picked up again
--   temporary error -> retried after 1, 2, 4, 8, 16, then every 30 minutes
--   permanent error -> failed_at is set, no more retries
-- A lease left by a call that died is picked up again after 2 minutes.
-- Temporary errors never give up on their own, so a long FCM or email outage
-- still ends in delivery. Only an alert still unsent 12 hours after it was
-- created is let go (failed_at, 'expired'), like the escalation job does:
-- news about yesterday morning would only confuse people.
-- A phone token FCM reports as gone is cleared from the member, so later
-- alerts don't keep trying it.
--
-- Needs two Vault secrets (set once per project, never in git):
--   project_url            https://<ref>.supabase.co
--   alerts_webhook_secret  same value as the function's ALERTS_WEBHOOK_SECRET

create extension if not exists pg_net with schema extensions;
create schema if not exists private;

alter table public.alerts
  add column attempts   integer not null default 0,
  add column claimed_at timestamptz,
  add column failed_at  timestamptz,
  add column retry_after timestamptz,
  add column last_error text check (char_length(last_error) <= 1000);

create index alerts_waiting_idx on public.alerts (id)
  where sent_at is null and failed_at is null;

-- Leases waiting alerts and returns everything needed to send them, as a
-- JSON array (see Alert in supabase/functions/send-alerts/deliver.ts).
create or replace function public.claim_alerts(p_limit integer default 50)
returns jsonb
language sql
set search_path = ''
as $$
  with expired as (
    update public.alerts
    set failed_at = now(), last_error = 'expired'
    where sent_at is null and failed_at is null
      and created_at < now() - interval '12 hours'
  ),
  claimed as (
    update public.alerts a
    set claimed_at = now(), attempts = a.attempts + 1
    where a.id in (
      select id from public.alerts
      where sent_at is null and failed_at is null
        and (claimed_at is null or claimed_at < now() - interval '2 minutes')
        and (retry_after is null or retry_after <= now())
        and created_at >= now() - interval '12 hours'
      order by id
      limit p_limit
      for update skip locked)
    returning a.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'step', c.step,
    'channel', c.channel,
    -- What the family calls the parent ("Mom"), set by the child at sign-up.
    'parent_name', coalesce(f.parent_name, 'your parent'),
    'recipient_name', r.display_name,
    'fcm_token', r.fcm_token,
    'emails', case when c.channel = 'email' then coalesce(
      (select jsonb_agg(jsonb_build_object('email', m.email,
                                           'name', coalesce(m.display_name, 'there'))
                        order by m.created_at, m.id)
       from public.members m
       where m.family_id = c.family_id and m.role = 'child' and m.email is not null),
      '[]'::jsonb) else '[]'::jsonb end,
    -- The same local-day rule as the escalation job: once the parent has said
    -- good morning, or someone has acknowledged that day, nothing more goes out.
    'checked_in', exists (
        select 1 from public.checkins k
        join public.schedules s on s.family_id = k.family_id
        where k.family_id = c.family_id
          and k.created_at >= c.day::timestamp at time zone s.time_zone
          and k.created_at < (c.day + 1)::timestamp at time zone s.time_zone)
      or exists (
        select 1 from public.alerts o
        where o.family_id = c.family_id and o.day = c.day
          and o.acknowledged_at is not null)
  ) order by c.id), '[]'::jsonb)
  from claimed c
  join public.families f on f.id = c.family_id
  left join public.members r on r.id = c.recipient_id;
$$;

create or replace function public.finish_alert(
  p_id public.alerts.id%type,
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
                         then now() + least(interval '1 minute' * 2 ^ (attempts - 1), interval '30 minutes') end
  where id = p_id and sent_at is null;

  -- Only if it's still the token that failed, not one the phone just renewed.
  update public.members m
  set fcm_token = null
  from public.alerts a
  where a.id = p_id and m.id = a.recipient_id and m.fcm_token = p_dead_token;
$$;

-- Calls the Edge Function when there's something to send.
create or replace function private.kick_alert_sender()
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
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
-- service role.
revoke all on function public.claim_alerts(integer) from public, anon, authenticated;
revoke all on function public.finish_alert(public.alerts.id%type, text, boolean, text) from public, anon, authenticated;
revoke all on function private.kick_alert_sender() from public, anon, authenticated;
grant execute on function public.claim_alerts(integer) to service_role;
grant execute on function public.finish_alert(public.alerts.id%type, text, boolean, text) to service_role;

select cron.schedule('send-alerts', '30 seconds', 'select private.kick_alert_sender()');
