-- Tests for alert delivery (supabase/migrations/*_alert_delivery.sql): how
-- the send-alerts Edge Function claims and finishes alert rows.
-- Run with `supabase test db`, or `pg_prove` against any database with the
-- migrations applied.

begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

-- Keep cases apart: start from no alerts.
delete from public.alerts;

create temp table fam as select gen_random_uuid() as id;
insert into public.families (id, name) select id, 'test' from fam;
insert into public.members (family_id, role, display_name, email, fcm_token, created_at)
select id, v.role, v.name, v.email, v.token, v.at from fam, (values
  ('parent', 'Mom', 'mom@x.test', 'tok-mom', '2026-01-01Z'::timestamptz),
  ('child',  'Sam', 'sam@x.test', 'tok-sam', '2026-01-02Z'),
  ('child',  'Lee', null,         null,      '2026-01-03Z'),
  ('child',  'Ana', 'ana@x.test', 'tok-ana', '2026-01-04Z')) as v(role, name, email, token, at);
insert into public.schedules (family_id, window_start, window_end, time_zone)
select id, '07:00', '09:00', 'America/New_York' from fam;

create function pg_temp.member(n text) returns uuid language sql as $$
  select id from public.members where display_name = n;
$$;
create function pg_temp.alert(p_day date, p_step int, p_channel text, p_to text) returns bigint
language sql as $$
  insert into public.alerts (family_id, day, step, channel, recipient_id)
  select id, p_day, p_step, p_channel, pg_temp.member(p_to) from fam
  returning id;
$$;
create function pg_temp.claim() returns jsonb language sql as $$
  select public.claim_alerts();
$$;

-- 1. A waiting urgent push is claimed with what the function needs.
create temp table a2 as select pg_temp.alert('2026-10-05', 2, 'urgent_push', 'Sam') as id;
create temp table c1 as select pg_temp.claim() as j;
select is(jsonb_array_length(j), 1, 'one alert claimed') from c1;
select is(j->0->>'parent_name', 'Mom', 'parent name') from c1;
select is(j->0->>'recipient_name', 'Sam', 'recipient name') from c1;
select is(j->0->>'fcm_token', 'tok-sam', 'recipient token') from c1;
select is(j->0->>'channel', 'urgent_push', 'channel') from c1;
select is((j->0->>'checked_in')::boolean, false, 'no check-in that day') from c1;
select is(j->0->'emails', '[]'::jsonb, 'no emails for a push') from c1;
select is((select attempts from public.alerts where id = a2.id), 1, 'attempt counted') from a2;

-- 2. A leased row isn't handed out twice.
select is(pg_temp.claim(), '[]'::jsonb, 'leased alert not claimed again');

-- 3. Sent: never picked up again, and a second finish changes nothing.
select public.finish_alert(id, null, false) from a2;
select isnt((select sent_at from public.alerts where id = a2.id), null, 'sent_at set') from a2;
update public.alerts set claimed_at = now() - interval '1 hour' where id = (select id from a2);
select is(pg_temp.claim(), '[]'::jsonb, 'sent alert not claimed again');
create temp table sent_at as select sent_at from public.alerts where id = (select id from a2);
select public.finish_alert(id, 'late error', false) from a2;
select is((select sent_at from public.alerts where id = a2.id), (select sent_at from sent_at),
          'finishing a sent alert again changes nothing') from a2;
select is((select last_error from public.alerts where id = a2.id), null, 'no error recorded on a sent alert') from a2;

-- 4. Temporary error: released and retried.
create temp table a3 as select pg_temp.alert('2026-10-05', 3, 'push', 'Ana') as id;
select pg_temp.claim();
select public.finish_alert(id, 'fcm 503', false) from a3;
select is((select row(claimed_at, failed_at, last_error)::text from public.alerts where id = a3.id),
          row(null::timestamptz, null::timestamptz, 'fcm 503')::text, 'released with the error kept') from a3;
select is(jsonb_array_length(pg_temp.claim()), 1, 'retried on the next run');
select is((select attempts from public.alerts where id = a3.id), 2, 'second attempt counted') from a3;

-- 5. A lease left by a call that died is picked up after 2 minutes.
update public.alerts set claimed_at = now() - interval '90 seconds' where id = (select id from a3);
select is(pg_temp.claim(), '[]'::jsonb, 'fresh lease kept');
update public.alerts set claimed_at = now() - interval '3 minutes' where id = (select id from a3);
select is(jsonb_array_length(pg_temp.claim()), 1, 'stale lease reclaimed');

-- 6. After 10 attempts it stops.
update public.alerts set attempts = 10 where id = (select id from a3);
select public.finish_alert(id, 'fcm 503', false) from a3;
select isnt((select failed_at from public.alerts where id = a3.id), null, 'gives up after 10 attempts') from a3;
select is(pg_temp.claim(), '[]'::jsonb, 'failed alert not claimed again');

-- 7. Permanent error stops at once.
create temp table a1 as select pg_temp.alert('2026-10-05', 1, 'push', 'Mom') as id;
select pg_temp.claim();
select public.finish_alert(id, 'no_token', true) from a1;
select isnt((select failed_at from public.alerts where id = a1.id), null, 'permanent error stops retries') from a1;

-- 8. Email goes to children with an address, never to the parent.
create temp table a4 as select pg_temp.alert('2026-10-05', 4, 'email', null) as id;
select is(pg_temp.claim()->0->'emails',
          '[{"email":"sam@x.test","name":"Sam"},{"email":"ana@x.test","name":"Ana"}]'::jsonb,
          'email to children with an address, in join order');

-- 9. A check-in that local day, and only that day, stops sending.
--    2026-10-06 in New York is 04:00Z on the 6th to 04:00Z on the 7th.
insert into public.checkins (family_id, member_id, source, created_at)
select id, pg_temp.member('Mom'), 'tap', '2026-10-06 03:59Z' from fam;
create temp table a5 as select pg_temp.alert('2026-10-06', 2, 'urgent_push', 'Sam') as id;
select is((pg_temp.claim()->0->>'checked_in')::boolean, false, 'check-in the evening before does not count');
insert into public.checkins (family_id, member_id, source, created_at)
select id, pg_temp.member('Mom'), 'steps', '2026-10-06 04:00Z' from fam;
update public.alerts set claimed_at = null where id = (select id from a5);
select is((pg_temp.claim()->0->>'checked_in')::boolean, true, 'check-in that local morning counts');

-- 10. Someone acknowledging that day stops the rest.
create temp table a6 as select pg_temp.alert('2026-10-07', 2, 'urgent_push', 'Sam') as id;
update public.alerts set sent_at = now(), acknowledged_at = now() where id = (select id from a6);
create temp table a7 as select pg_temp.alert('2026-10-07', 3, 'push', 'Ana') as id;
select is((pg_temp.claim()->0->>'checked_in')::boolean, true, 'acknowledged day sends nothing more');

-- 11. The parent's name falls back when unset.
update public.members set display_name = null where role = 'parent';
create temp table a8 as select pg_temp.alert('2026-10-08', 2, 'urgent_push', 'Sam') as id;
select is(pg_temp.claim()->0->>'parent_name', 'your parent', 'fallback parent name');

-- 12. An alert left unsent for 12 hours is let go, not sent late.
delete from public.alerts;
create temp table a10 as select pg_temp.alert('2026-10-09', 2, 'urgent_push', 'Sam') as id;
update public.alerts set created_at = now() - interval '13 hours' where id = (select id from a10);
select is(pg_temp.claim(), '[]'::jsonb, 'stale alert not sent');
select is((select last_error from public.alerts where id = a10.id and failed_at is not null), 'expired',
          'stale alert marked expired') from a10;

-- 13. The kick calls the function only when something is waiting.
delete from public.alerts;
delete from net.http_request_queue;
delete from vault.secrets where name in ('project_url', 'alerts_webhook_secret');
select private.kick_alert_sender();
select is((select count(*)::int from net.http_request_queue), 0, 'no call when nothing is waiting');
create temp table a9 as select pg_temp.alert('2026-10-09', 2, 'urgent_push', 'Sam') as id;
select private.kick_alert_sender();
select is((select count(*)::int from net.http_request_queue), 0, 'no call without the Vault secrets');
select vault.create_secret('https://ref.supabase.co', 'project_url');
select vault.create_secret('s3cret', 'alerts_webhook_secret');
select private.kick_alert_sender();
select is((select url || ' ' || (headers->>'x-alerts-secret') from net.http_request_queue),
          'https://ref.supabase.co/functions/v1/send-alerts s3cret', 'one call with the secret');

-- 14. Only the server can claim or finish alerts.
select ok(not has_function_privilege('authenticated', 'public.claim_alerts(integer)', 'execute')
          and not has_function_privilege('anon', 'public.claim_alerts(integer)', 'execute')
          and not has_function_privilege('authenticated', 'public.finish_alert(bigint, text, boolean)', 'execute'),
          'API roles cannot claim or finish alerts');

select * from finish();
rollback;
