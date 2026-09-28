-- Tests for the uptime watcher (supabase/migrations/*_uptime_watcher.sql).
-- Run with `supabase test db`.

begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

delete from public.heartbeats where job in ('escalation', 'send-alerts');
delete from net.http_request_queue;
delete from vault.secrets where name = 'uptime_ping_url';

-- 1. Neither job has ever run: no ping.
select private.ping_uptime_watcher();
select is((select count(*)::int from net.http_request_queue), 0, 'no ping with no heartbeats at all');

-- 2. Only one of the two jobs is healthy: still no ping.
insert into public.heartbeats (job, last_run_at) values ('escalation', now());
select private.ping_uptime_watcher();
select is((select count(*)::int from net.http_request_queue), 0, 'no ping while only one job is healthy');

-- 3. Both healthy, but no Vault secret yet: still no ping, and it doesn't error.
insert into public.heartbeats (job, last_run_at) values ('send-alerts', now());
select private.ping_uptime_watcher();
select is((select count(*)::int from net.http_request_queue), 0, 'no ping without the Vault secret');

-- 4. Both healthy and the secret is set: one GET to the ping URL.
select vault.create_secret('https://hc-ping.com/test-uuid', 'uptime_ping_url');
select private.ping_uptime_watcher();
select is((select url from net.http_request_queue), 'https://hc-ping.com/test-uuid', 'one ping with the URL');
select is((select method from net.http_request_queue), 'GET', 'the ping is a GET');

-- 5. Either heartbeat gone stale: no ping.
delete from net.http_request_queue;
update public.heartbeats set last_run_at = now() - interval '6 minutes' where job = 'escalation';
select private.ping_uptime_watcher();
select is((select count(*)::int from net.http_request_queue), 0, 'no ping while a heartbeat is stale');

-- 6. Only the server can run it.
select ok(not has_function_privilege('anon', 'private.ping_uptime_watcher()', 'execute'),
          'anon cannot run the uptime watcher');

-- 7. Scheduled every 5 minutes.
select is((select schedule from cron.job where jobname = 'uptime-watcher'), '*/5 * * * *',
          'pg_cron pings every 5 minutes');

select * from finish();
rollback;
