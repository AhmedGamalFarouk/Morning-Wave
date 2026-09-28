-- Uptime watcher.
--
-- Every 5 minutes, private.ping_uptime_watcher() checks that both pg_cron
-- jobs are still alive (each writes a row in public.heartbeats: see
-- 20260927000300_escalation.sql and 20260927000400_alert_delivery.sql) and,
-- only while both are healthy, pings an external dead man's switch (a free
-- healthchecks.io check by default) through pg_net.
--
-- If the backend stops running -- Postgres down, pg_cron stuck, the project
-- paused -- nothing pings the switch, and the outside service emails Ahmed
-- on its own after its grace period. This job never sends mail or raises an
-- alert itself, so there's nothing here that can also go silently down.
--
-- Needs one Vault secret (set once per project, never in git):
--   uptime_ping_url   the check's ping URL, e.g. https://hc-ping.com/<uuid>

create or replace function private.ping_uptime_watcher()
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_url text;
begin
  if (select count(*) from public.heartbeats
      where job in ('escalation', 'send-alerts')
        and last_run_at > now() - interval '5 minutes') < 2 then
    return;
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'uptime_ping_url';
  if v_url is null then
    raise warning 'uptime watcher: Vault secret uptime_ping_url is not set';
    return;
  end if;

  perform net.http_get(url := v_url, timeout_milliseconds := 10000);
end;
$$;

-- Server only: no API role may call this.
revoke all on function private.ping_uptime_watcher() from public, anon, authenticated;

select cron.schedule('uptime-watcher', '*/5 * * * *', 'select private.ping_uptime_watcher()');
