# send-alerts

Delivers the alert rows the missed-morning job inserts: FCM pushes (high priority, the app's `urgent` channel
for children, `gentle` for the parent's nudge) and emails through Brevo's free tier. Words live in
`wording.ts` and follow `docs/design-language.md`.

How it's called, retried and kept from double-sending is described at the top of
`supabase/migrations/20260927000400_alert_delivery.sql`.

## Secrets (never in git)

Function secrets (`supabase secrets set NAME=value`):

| Name                    | What                                                                                                           |
| ----------------------- | -------------------------------------------------------------------------------------------------------------- |
| `ALERTS_WEBHOOK_SECRET` | Any long random string. Only callers that send it in `x-alerts-secret` get in.                                 |
| `FCM_SERVICE_ACCOUNT`   | The Firebase service account JSON (Project settings, Service accounts, Generate new private key), as one line. |
| `BREVO_API_KEY`         | Brevo, SMTP & API, API keys.                                                                                   |
| `ALERT_EMAIL_FROM`      | A sender address verified in Brevo.                                                                            |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase.

Vault secrets (SQL editor), read by the every-30-seconds job:

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<same value as ALERTS_WEBHOOK_SECRET>', 'alerts_webhook_secret');
```

## Deploy

```sh
supabase functions deploy send-alerts
```

`supabase/config.toml` turns off JWT checks for this function: the caller is the database, which proves itself
with the shared secret instead of a user token.

## Health

The every-30-seconds job writes the `send-alerts` row in `heartbeats` only while no alert has waited more than
10 minutes, so the uptime check on heartbeats also catches a bad secret, a failing function, or an FCM or
email outage.

### Uptime watcher

`supabase/migrations/20260928000100_uptime_watcher.sql` pings a free external dead man's switch every 5
minutes, but only while both the `escalation` and `send-alerts` heartbeats are fresh. If the backend stops
running, nothing pings it, and the outside service emails Ahmed itself after its grace period.

Set up once (Ahmed, with his own hands or a local session — not from cloud):

1. At [healthchecks.io](https://healthchecks.io), free account, create a check named e.g. "Morning Wave
   heartbeat". Set its period to 10 minutes and grace time to 10 minutes, and add
   myfakemail@atomicmail.io (or Ahmed's own address) as the alert contact.
2. Copy its ping URL (`https://hc-ping.com/<uuid>`).
3. In the Supabase SQL editor on the live project:
   ```sql
   select vault.create_secret('<ping URL from step 2>', 'uptime_ping_url');
   ```

No `uptime_ping_url` secret means the watcher logs a warning and does nothing, so it's safe to merge and
deploy before this is set up.

## Test

```sh
cd supabase/functions/send-alerts && deno test
```

Database side: `supabase test db` runs `supabase/tests/alert_delivery_test.sql` (CI does too).
