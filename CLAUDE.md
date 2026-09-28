# Morning Wave

Daily check-in app for older parents who live alone, paid for by their adult children. The parent taps once each morning; if they don't, the family hears about it gently.
- Never call the app "Sunnyside". Tone is "stay in touch", never "monitor".
- Owner: Ahmed (GitHub AhmedGamalFarouk). Plan: https://claude.ai/artifact/MS4X43KhyZyjkK34NrwUUh
- Price: $59.99/yr family plan paid by the child; the parent is always free.

## Stack
- Flutter, Android only (Google Play). App ID `app.morningwave` (permanent).
- Supabase: Postgres + RLS, Auth (Google for children, anonymous for parents), pg_cron, Edge Functions (`supabase/functions/send-alerts`).
- Firebase FCM + Crashlytics, Brevo email, RevenueCat. Budget $25 total: no paid services.

## Token budget rules (Ahmed, 2026-09-28; override older habits)
- One implementation thread at a time; a second only for truly independent work, never more than two live.
- Default model Sonnet. Opus only for schema/security design or a bug Sonnet failed to fix.
- One review per PR: the implementing thread runs /code-review once on its own diff before ready. No standing reviewer, no skill-pass thread, no re-review unless it found a P1/P2.
- Skills are opt-in. ponytail, clean-code-guard, gstack, impeccable, find-skills never run automatically. impeccable only for a new screen; /cso only for auth, RLS or secrets changes; one run each.
- No routines or polling. Subscribe to PR activity only on a PR the thread owns; unsubscribe on merge.
- Read only the files the task names. grep and targeted reads, no whole-repo scans, don't reread unchanged files.
- Keep threads short: finish, merge, resolve. New work gets a fresh thread.
- Threads don't relay chatter through the coordinator; report once when done or blocked.

## PRs and branches
- One branch per PR, no stacked PRs, delete the branch on merge. Target state: main plus at most one open PR.
- Merge policy: when CI is green and the self-review is clean, the owning thread merges without asking Ahmed.
- CI (`.github/workflows`): `app.yml` (flutter analyze + test, every PR), `db.yml` (pgTAP, on `supabase/**`), `functions.yml` (Deno, on `supabase/functions/**`).
- Never commit secrets: `config/dev.json` and `android/app/google-services.json` stay uncommitted. Release builds fail without google-services.json on purpose.

## Where work runs
- Cloud by default: code, tests (Flutter, Deno, `supabase test db`), reviews.
- Local session on Ahmed's PC (`G:\Code\FLUTTER\morningwave`, C: nearly full) only for his Chrome, live Supabase changes or secrets, and phone builds. Stop it when the step is done.
- Live changes need Ahmed's own words naming the change, written in that thread.
- Cloud can't reach live Supabase: route that step to a local session, don't block on it.
- Cloud setup: Flutter via `git clone --depth 1 -b 3.47.5 https://github.com/flutter/flutter.git /tmp/flutter`; Deno via `npx -y deno`; pgTAP via `sudo -n dockerd &` then `npx -y supabase@2.118.0` with `db start`, `db reset`, `test db`.

## Design
- Follow `docs/design-language.md` on any UI change; read only the section you need. `DESIGN.md` has palette/type/motion, `PRODUCT.md` the product facts.
- Warm, never "monitoring". Body 20sp+, parent primary action 28sp+. No failure words for the parent.
- Titles use `WholeWordsText` (no mid-word breaks at 200% text).

## Live setup (public values only)
- Supabase: https://vlxqxlnvrhqsixdskorf.supabase.co, publishable key `sb_publishable_IL2aWS_MNLCG0S38Q5QBbA_URT44fZl`. Google + anonymous sign-in on (anon ~10/h/IP), CAPTCHA off.
- Google Cloud project `morning-wave`: Web client `565279408877-al5t9jtc1oj6l6r1q4r2op8d5hk7f9gv.apps.googleusercontent.com` plus an Android client (debug SHA-1). Consent screen in Testing.
- Live as of 2026-09-27: all migrations applied, send-alerts deployed, heartbeats ticking, webhook and Vault secrets set, Firebase app registered.
- Privacy contact: myfakemail@atomicmail.io.

## Schema contract
- `create_family(parent_name, my_name, time_zone)` also creates the schedule; rejects anonymous users.
- `join_family(code, my_name)` returns setof; `[]` on a wrong code. Parent code is anonymous-only; child code rejects anonymous.
- `reinvite_parent` / code rotation reject anonymous. Only the parent checks in.
- `members.email` is server-only. `time_zone` must pass `private.is_known_zone`. `acknowledged_at` is set only on a deliberate tap.
- Away mode: checks resume the morning after the return day.

## Dates
- Closed test from 2026-12-14. Play launch 2027-01-19. Mother's Day push to 2027-05-09.

## To-dos before the closed test
- FCM service-account key via the secrets script, then a test push to Ahmed's phone.
- Delete merged branches.
- Uptime watcher on heartbeats.
- Device end-to-end test.
- Remove the calling stub.
- CAPTCHA before public launch.
- Then plan step 4: voice, photos, paywall.
