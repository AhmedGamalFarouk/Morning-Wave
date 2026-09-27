# Morning Wave waitlist site

A static one-page site. Signups go straight from the browser into the `waitlist`
table in Supabase. No build step, no server, no paid services.

## Set up

1. Apply the migration `supabase/migrations/20260927000100_waitlist.sql`
   (`supabase db push`, or paste it into the Supabase SQL editor).
2. In `config.js`, fill in the project URL and the publishable (anon) key from
   Supabase: Project Settings > API. Never use the service_role or secret key.
3. In `privacy.html`, replace `CONTACT-EMAIL` with a real address.

## Deploy on Cloudflare Pages (free)

Connect the GitHub repo in Cloudflare Pages, then set:

- Build command: none
- Build output directory: `web/waitlist`

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
