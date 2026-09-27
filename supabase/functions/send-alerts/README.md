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
supabase functions deploy send-alerts --no-verify-jwt
```

`--no-verify-jwt` because the caller is the database, which proves itself with the shared secret instead of a
user token.

## Test

```sh
cd supabase/functions/send-alerts && deno test
```

Database side: `supabase test db` runs `supabase/tests/alert_delivery_test.sql`.
