# Design

The visual system behind `docs/design-language.md`. That document says how
Morning Wave should feel; this one records the decisions that make it so.
Code is the source of truth: `lib/theme/` and `lib/widgets/`.

## World

A greeting card left on the kitchen table at sunrise. Warm cream paper, a
painted sun, notes and photos that sit on the paper like real objects. No
Material chrome: no app bars, no default cards, no status chips.

## Color (`lib/theme/palette.dart`)

| Token | Hex | Use |
| --- | --- | --- |
| paper | `#FBF3E6` | Every screen background |
| paperDeep | `#F5E6D0` | Quiet fills, resting states |
| card | `#FFFAF2` | Cards and notes |
| ink | `#3A281D` | Text and the main button |
| inkSoft | `#6B5244` | Secondary lines (about 6:1 on paper) |
| sunCore / sun / sunEdge | `#FFD77A` / `#F6B94B` / `#EE9A4D` | The sun, hearts |
| glow | `#FBD3A6` | Sun glow, "heard" hero |
| peach, sky, sage | `#F4C7AE`, `#CFE0EA`, `#7E9F83` | Accents |

Light only for now: the app is used in the morning, in daylight. A dark
scheme is still owed before launch.

## Type (`lib/theme/app_theme.dart`)

- **Fraunces** (variable, SOFT 100) for everything that speaks: greetings,
  the sun's words, family notes.
- **Atkinson Hyperlegible Next** (designed for low vision) for everything
  that explains.
- Parent side: body 20sp minimum (`bodyMedium`), 22sp for lines under the
  greeting (`bodyLarge`), the sun's words 28sp (`headlineMedium`).
- Both fonts are OFL and bundled, so nothing downloads at runtime.

## Surfaces

`PaperCard`: 22dp radius, warm brown shadow (never grey), no border.
Buttons are ink stadiums, 60dp tall. Hearts and suns are painted, never
emoji, so they look the same on every phone.

## Motion (`lib/theme/motion.dart`)

- The sun breathes over 4.8s and its rays turn once every 150s.
- Tap: the sun sinks slightly, then swells, stretches its rays and lets
  light motes and a few hearts drift up over 1.6s, with one haptic tick.
- Words change by fading the old line out before the new one arrives.
- System "Remove animations" stops the breathing and skips the swell.

## Language

Every state is something a person did: "Mom said good morning", "Haven't
heard from Mom yet", "You're away. Your family knows." The widget tests
fail if parent or child copy contains miss, monitor, status, alert, fail,
inactive, compliance or track.
