# Morning Wave waitlist site

A static one-page site. Signups go straight from the browser into the `waitlist`
table in Supabase. No build step, no server, no paid services.

## Set up

1. Apply the migration `supabase/migrations/20260927000100_waitlist.sql`
   (`supabase db push`, or paste it into the Supabase SQL editor).
2. In `config.js`, fill in the project URL and the publishable (anon) key from
   Supabase: Project Settings > API. Never use the service_role or secret key.

## Deploy on Cloudflare Pages (free)

Connect the GitHub repo in Cloudflare Pages, then set:

- Build command: none
- Build output directory: `web/waitlist`

## Before launch

- Replace the waitlist-only privacy page with the full policy and terms for
  the app (plan phase 5).
- Double opt-in: signups aren't confirmed by email yet, so a mistyped or fake
  address still lands in the table. Add a confirmation email before the launch
  email goes out (plan phase 5). Doing it for $0 needs a free transactional
  email tier (Resend or Brevo) plus an Edge Function, and a verified sending
  domain.
- Look and feel follow the app's `DESIGN.md` and `lib/theme/palette.dart`
  (paper, ink, sun; Fraunces and Atkinson Hyperlegible Next). Keep them in step.

## Try it locally

```sh
cd web/waitlist && python3 -m http.server 8000
```

## Track where signups come from

Add `?ref=` to links you share, for example `?ref=reddit-agingparents` or
`?ref=tiktok-1`. It is saved in the `source` column.

## Read signups

Supabase dashboard: Table Editor > `waitlist`. The site's key can only add rows,
never read them. All-Android families (the phase 1 goal is 30):

```sql
select count(*) from waitlist where own_phone = 'android' and parent_phone = 'android';
```
