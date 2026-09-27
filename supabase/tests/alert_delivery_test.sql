-- Tests for alert delivery (supabase/migrations/*_alert_delivery.sql): how
-- the send-alerts Edge Function claims and finishes alert rows.
-- Run with `supabase test db`. Alert days are relative to today, so the
-- 12-hour cutoff doesn't depend on when the tests run.

begin;
create extension if not exists pgtap with schema extensions;
select plan(53);

-- Keep cases apart: start from no alerts.
delete from public.alerts;

create temp table fam as select gen_random_uuid() as id;
insert into public.families (id, parent_name) select id, 'Mom' from fam;
create function pg_temp.member(p_role text, p_name text, p_email text, p_token text, p_joined timestamptz)
returns void language sql as $$
  with u as (insert into auth.users (id) values (gen_random_uuid()) returning id)
  insert into public.members (family_id, user_id, role, display_name, email, fcm_token, created_at)
  select fam.id, u.id, p_role, p_name, p_email, p_token, p_joined from fam, u;
$$;
select pg_temp.member('parent', 'Mom', 'mom@x.test', 'tok-mom', '2026-01-01Z');
select pg_temp.member('child',  'Sam', 'sam@x.test', 'tok-sam', '2026-01-02Z');
select pg_temp.member('child',  'Lee', null,         null,      '2026-01-03Z');
select pg_temp.member('child',  'Ana', 'ana@x.test', 'tok-ana', '2026-01-04Z');
insert into public.schedules (family_id, window_start, window_end, time_zone)
select id, '21:00', '23:59', 'UTC' from fam;

create function pg_temp.member(n text) returns uuid language sql as $$
  select id from public.members where display_name = n;
$$;
-- An alert for n days from today.
create function pg_temp.alert(n int, p_step int, p_channel text, p_to text) returns uuid
language sql as $$
  insert into public.alerts (family_id, day, step, channel, recipient_id)
  select id, current_date + n, p_step, p_channel, pg_temp.member(p_to) from fam
  returning id;
$$;
create function pg_temp.claim() returns jsonb language sql as $$
  select public.claim_alerts();
$$;
create function pg_temp.wait(a uuid) returns interval language sql as $$
  select retry_after - now() from public.alerts where id = a;
$$;

-- 1. A ready urgent push is claimed with what the function needs.
create temp table a2 as select pg_temp.alert(1, 2, 'urgent_push', 'Sam') as id;
create temp table c1 as select pg_temp.claim() as j;
select is(jsonb_array_length(j), 1, 'one alert claimed') from c1;
select is(j->0->>'id', (select id::text from a2), 'its id') from c1;
select is(j->0->>'parent_name', 'Mom', 'parent name from the family') from c1;
select is(j->0->>'fcm_token', 'tok-sam', 'recipient token') from c1;
select is(j->0->>'channel', 'urgent_push', 'channel') from c1;
select is((j->0->>'checked_in')::boolean, false, 'no check-in that day') from c1;
select is(j->0->'emails', '[]'::jsonb, 'no emails for a push') from c1;
select is((select attempts from public.alerts where id = a2.id), 1, 'attempt counted') from a2;

-- 2. A leased row isn't handed out twice.
select is(pg_temp.claim(), '[]'::jsonb, 'leased alert not claimed again');

-- 3. Sent: never picked up again, and a second finish changes nothing.
select public.finish_alert(id, null) from a2;
select isnt((select sent_at from public.alerts where id = a2.id), null, 'sent_at set') from a2;
update public.alerts set claimed_at = now() - interval '1 hour' where id = (select id from a2);
select is(pg_temp.claim(), '[]'::jsonb, 'sent alert not claimed again');
create temp table sent as select sent_at from public.alerts where id = (select id from a2);
select public.finish_alert(id, 'late error') from a2;
select is((select sent_at from public.alerts where id = a2.id), (select sent_at from sent),
          'finishing a sent alert again changes nothing') from a2;
select is((select last_error from public.alerts where id = a2.id), null, 'no error recorded on a sent alert') from a2;

-- 4. Temporary error: released, retried after a growing wait.
create temp table a3 as select pg_temp.alert(1, 3, 'push', 'Ana') as id;
select pg_temp.claim();
select public.finish_alert(id, 'fcm 503') from a3;
select is((select row(claimed_at, failed_at, last_error)::text from public.alerts where id = a3.id),
          row(null::timestamptz, null::timestamptz, 'fcm 503')::text, 'released with the error kept') from a3;
select is(pg_temp.wait(id), interval '1 minute', 'first retry after a minute') from a3;
select is(pg_temp.claim(), '[]'::jsonb, 'not retried before then');
update public.alerts set retry_after = now() where id = (select id from a3);
select is(jsonb_array_length(pg_temp.claim()), 1, 'retried once the wait is over');
select public.finish_alert(id, 'fcm 503') from a3;
select is(pg_temp.wait(id), interval '2 minutes', 'second wait doubles') from a3;

-- 5. A lease left by a call that died is picked up after 2 minutes.
update public.alerts set retry_after = null, claimed_at = now() - interval '90 seconds'
where id = (select id from a3);
select is(pg_temp.claim(), '[]'::jsonb, 'fresh lease kept');
update public.alerts set claimed_at = now() - interval '3 minutes' where id = (select id from a3);
select is(jsonb_array_length(pg_temp.claim()), 1, 'stale lease reclaimed');

-- 6. Ten quick temporary failures don't give up: an outage of a few minutes
--    still ends in delivery. The wait stops growing at 30 minutes, and a
--    huge attempt count doesn't overflow.
create function pg_temp.fail_again(p uuid) returns void language sql as $$
  update public.alerts set retry_after = null, claimed_at = null where id = p;
  select public.claim_alerts();
  select public.finish_alert(p, 'fcm 503');
$$;
select pg_temp.fail_again(id) from a3, generate_series(1, 10);
select is((select failed_at from public.alerts where id = a3.id), null, 'still waiting after 10 more failures') from a3;
select is(pg_temp.wait(id), interval '30 minutes', 'wait capped at 30 minutes') from a3;
update public.alerts set attempts = 5000 where id = (select id from a3);
select lives_ok($$ select public.finish_alert(id, 'fcm 503') from a3 $$, 'no overflow on many attempts');
update public.alerts set retry_after = now() where id = (select id from a3);
select is(jsonb_array_length(pg_temp.claim()), 1, 'claimable again after the wait');

-- 7. Permanent error stops at once.
create temp table a1 as select pg_temp.alert(1, 1, 'push', 'Mom') as id;
select pg_temp.claim();
select public.finish_alert(id, 'no_token', true) from a1;
select isnt((select failed_at from public.alerts where id = a1.id), null, 'permanent error stops retries') from a1;
select is((select retry_after from public.alerts where id = a1.id), null, 'no retry planned') from a1;

-- 8. A token FCM says is gone is cleared, but only if it hasn't changed since.
create temp table a1b as select pg_temp.alert(2, 2, 'urgent_push', 'Ana') as id;
select pg_temp.claim();
select public.finish_alert(id, 'fcm 404', true, 'tok-old') from a1b;
select is((select fcm_token from public.members where display_name = 'Ana'), 'tok-ana', 'renewed token kept');
select public.finish_alert(id, 'fcm 404', true, 'tok-ana') from a1b;
select is((select fcm_token from public.members where display_name = 'Ana'), null, 'dead token cleared');
update public.members set fcm_token = 'tok-ana' where display_name = 'Ana';

-- 9. Email goes to children with an address, never to the parent.
create temp table a4 as select pg_temp.alert(1, 4, 'email', null) as id;
select is(pg_temp.claim()->0->'emails',
          '[{"email":"sam@x.test","name":"Sam"},{"email":"ana@x.test","name":"Ana"}]'::jsonb,
          'email to children with an address, in join order');

-- 10. The parent's own check-in from the start of that local day stops
--     sending; one the evening before, a child's, or a future-dated one
--     (a phone with a wrong clock) doesn't.
create temp table today as select current_date::timestamp at time zone 'UTC' as starts;
insert into public.checkins (family_id, member_id, source, created_at)
select id, pg_temp.member('Mom'), 'tap', (select starts from today) - interval '1 minute' from fam;
insert into public.checkins (family_id, member_id, source, created_at)
select id, pg_temp.member('Sam'), 'tap', (select starts from today) from fam;
insert into public.checkins (family_id, member_id, source, created_at)
select id, pg_temp.member('Mom'), 'tap', now() + interval '10 days' from fam;
create temp table a5 as select pg_temp.alert(0, 2, 'urgent_push', 'Sam') as id;
select is((pg_temp.claim()->0->>'checked_in')::boolean, false,
          'the evening before, a child tapping, or a future date does not count');
insert into public.checkins (family_id, member_id, source, created_at)
select id, pg_temp.member('Mom'), 'steps', (select starts from today) from fam;
update public.alerts set claimed_at = null where id = (select id from a5);
select is((pg_temp.claim()->0->>'checked_in')::boolean, true, 'her check-in that morning counts');

-- 10b. An unknown zone (which the schema should already stop) doesn't abort
--      the claim; the alert still goes out.
-- Lift whatever guards the schema puts on time_zone (checks or triggers),
-- only inside this rolled-back test.
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.schedules'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%time_zone%' loop
    execute format('alter table public.schedules drop constraint %I', c);
  end loop;
end $$;
alter table public.schedules disable trigger user;
update public.schedules set time_zone = 'Mars/Olympus' where family_id = (select id from fam);
update public.alerts set claimed_at = null where id = (select id from a5);
select is((pg_temp.claim()->0->>'checked_in')::boolean, false, 'unknown zone: claim still works');
update public.schedules set time_zone = 'UTC' where family_id = (select id from fam);
alter table public.schedules enable trigger user;

-- 11. Someone acknowledging that day stops the rest.
create temp table a6 as select pg_temp.alert(4, 2, 'urgent_push', 'Sam') as id;
update public.alerts set sent_at = now(), acknowledged_at = now() where id = (select id from a6);
create temp table a7 as select pg_temp.alert(4, 3, 'push', 'Ana') as id;
select is((pg_temp.claim()->0->>'checked_in')::boolean, true, 'acknowledged day sends nothing more');

-- 12. Same-moment inserts (catch-up after an outage) come out in step order.
delete from public.alerts;
insert into public.alerts (family_id, day, step, channel, recipient_id)
select id, current_date + 5, s, c, r from fam, (values
  (4, 'email', null::uuid), (1, 'push', pg_temp.member('Mom')),
  (3, 'push', pg_temp.member('Ana')), (2, 'urgent_push', pg_temp.member('Sam'))) v(s, c, r);
select is((select array_agg((e->>'step')::int) from jsonb_array_elements(pg_temp.claim()) e),
          '{1,2,3,4}', 'claimed in step order');

-- 13. The cutoff is 12 hours after that morning's window closed, not after
--     the row was inserted.
delete from public.alerts;
create temp table a10 as select pg_temp.alert(-3, 2, 'urgent_push', 'Sam') as id;
select is(pg_temp.claim(), '[]'::jsonb, 'a days-old morning is not sent, even when just inserted');
select is((select last_error from public.alerts where id = a10.id and failed_at is not null), 'expired',
          'and is marked expired') from a10;
create temp table a11 as select pg_temp.alert(1, 2, 'urgent_push', 'Sam') as id;
update public.alerts set created_at = now() - interval '13 hours' where id = (select id from a11);
select is(jsonb_array_length(pg_temp.claim()), 1, 'an old row for a morning still in reach is sent');

-- 14. The kick: heartbeat while healthy, a call only when something is ready.
delete from public.alerts;
delete from public.heartbeats where job = 'send-alerts';
delete from net.http_request_queue;
delete from vault.secrets where name in ('project_url', 'alerts_webhook_secret');
select private.kick_alert_sender();
select is((select count(*)::int from net.http_request_queue), 0, 'no call when nothing is waiting');
select isnt((select last_run_at from public.heartbeats where job = 'send-alerts'), null, 'healthy heartbeat');
create temp table a9 as select pg_temp.alert(1, 2, 'urgent_push', 'Sam') as id;
select private.kick_alert_sender();
select is((select count(*)::int from net.http_request_queue), 0, 'no call without the Vault secrets');
select vault.create_secret('https://ref.supabase.co', 'project_url');
select vault.create_secret('s3cret', 'alerts_webhook_secret');
update public.alerts set retry_after = now() + interval '1 minute' where id = (select id from a9);
select private.kick_alert_sender();
select is((select count(*)::int from net.http_request_queue), 0, 'no call while the only alert waits to retry');
update public.alerts set retry_after = null where id = (select id from a9);
select private.kick_alert_sender();
select is((select url || ' ' || (headers->>'x-alerts-secret') from net.http_request_queue),
          'https://ref.supabase.co/functions/v1/send-alerts s3cret', 'one call with the secret');
update public.heartbeats set last_run_at = '2000-01-01Z' where job = 'send-alerts';
update public.alerts set created_at = now() - interval '11 minutes' where id = (select id from a9);
select private.kick_alert_sender();
select is((select last_run_at from public.heartbeats where job = 'send-alerts'), '2000-01-01Z',
          'heartbeat goes stale while an alert has waited over 10 minutes');

-- 15. Only the server can claim or finish alerts or run the kick.
select ok(not has_function_privilege(r, f, 'execute'), format('%s cannot run %s', r, f))
from unnest(array['anon', 'authenticated']) r,
     unnest(array['public.claim_alerts(integer)', 'public.finish_alert(uuid, text, boolean, text)',
                  'private.kick_alert_sender()', 'private.alert_deadline(uuid, date, timestamptz)',
                  'private.local_day_start(uuid, date)']) f;

select * from finish();
rollback;
