# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

- **Parent** (older adult living alone). Opens the app once each morning to say
  good morning to their family. May have low vision, shaky hands, and little
  patience for software. Must understand the screen without instructions.
- **Adult child** (pays for the family plan). Glances at the app to answer one
  question: "How is Mom?" Often busy, often in another city or country.

## Product Purpose

A daily check-in ritual: the parent taps once to say "good morning", the
family sees it, and if a morning passes quietly the family is gently told so
they can reach out. Success is a parent who keeps the ritual because it feels
like a hello, and a child who feels reassured at a glance.

## Positioning

A warm family ritual, not a monitoring product. The parent is never evaluated
or watched; they are sending a small "I'm okay" to people who love them.

## Operating Context

- Morning, at home, often before or with the first coffee.
- One primary action per day on the parent side.
- The child checks from work, commute, or a different time zone.

## Capabilities and Constraints

- Flutter, Android first, Google Play only. Supabase backend, FCM push.
- Free parent side; $59.99/yr family plan paid by the child.
- $25 total cash budget before launch: no paid fonts, assets, or services.
- Voice notes, mood, photos and "I'm away" are planned; backend for them is
  undecided.

## Brand Commitments

- Name: **Morning Wave** (never "Sunnyside", the old working name).
- `docs/design-language.md` is the binding design language: sunrise warmth,
  human language over status labels, the Morning Sun as the parent's one
  action, calm motion, no generic Material look.
- Say "stay in touch", never "monitor".

## Evidence on Hand

No real family photos, testimonials, or user data yet. Placeholder content
must be clearly illustrative and replaced before launch.

## Product Principles

1. One action for the parent. Nothing competes with the sun.
2. People, not statistics. Every state is written as something a family
   member did or said.
3. The parent never sees failure, blame, or alarm language.
4. The child's first feeling is "Mom is okay"; detail comes after.
5. Emotional never means complicated.

## Accessibility & Inclusion

- Parent body text 20sp minimum; primary action text 28sp or larger.
- Touch targets well above 48dp on the parent side; forgiving taps, easy undo.
- Strong contrast (WCAG AA at least) and support for system font scaling.
- Respect the system "Remove animations" setting.
