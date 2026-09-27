# Morning Wave

A daily check-in for parents who live alone, so their grown children can stay
in touch. Flutter app, Android only for now.

## Run it

```sh
flutter pub get
flutter run
```

That works on a fresh clone: Supabase, push and crash reporting stay off and
a line in the debug log says so. Once `config/dev.json` exists (below), run
`flutter run --dart-define-from-file=config/dev.json` to connect Supabase.

With Supabase connected the app starts at sign-in: the grown child signs in
with Google, names their parent and gets a family code; the parent taps
"I have a code", types it and lands on the Morning Sun, without an account.
Without config it previews the home screens instead.

To preview the child's home instead of the parent's, add
`--dart-define=PREVIEW=child` (or `child-waiting`, `child-away`). Screens use
placeholder data from `lib/placeholder/family.dart` until the backend is wired.

## Design

`docs/design-language.md` is the emotional design language every screen
follows. `DESIGN.md` records the palette, type, surfaces and motion that
implement it, and `PRODUCT.md` the product facts design work relies on.

## Config you fill in (never committed)

| File | What goes in it | Where to get it |
| --- | --- | --- |
| `config/dev.json` | Copy `config/example.json`, set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` | Supabase dashboard, Project Settings > API Keys |
| `GOOGLE_WEB_CLIENT_ID` in `config/dev.json` | The **Web** OAuth client ID (Google sign-in hands Supabase a token for it) | Google Cloud console, APIs & Services > Credentials. Also create an **Android** client for `app.morningwave` with your debug SHA-1, and turn on Google (with this client ID) and Anonymous sign-ins in Supabase Auth > Providers |
| `android/app/google-services.json` | Firebase Android config for package `app.morningwave` | Firebase console, Project settings > Your apps > Add Android app |

Both paths are in `.gitignore`. When `google-services.json` is present the
Google Services and Crashlytics Gradle plugins switch on automatically.
Release builds (`flutter build apk`) fail without it, so a build without
crash reporting can't ship by accident.

## What is wired

- `supabase_flutter`, initialised from `config/*.json` via `--dart-define-from-file`.
- `firebase_core`, `firebase_messaging`, `firebase_crashlytics` (Flutter and
  async errors go to Crashlytics).
- `flutter_local_notifications` with an `urgent` channel, shown in Android
  settings as "Family messages" (max importance). Server pushes for missed
  check-ins should set `android.notification.channel_id` to `urgent`. Pushes
  that arrive while the app is open are shown through this channel too.
- Android 13+ notification permission is requested on the home screen.
- The launch screen uses the cream paper colour, so there is no white flash.

## Checks

CI (`.github/workflows/app.yml`) runs `dart format`, `flutter analyze` and
`flutter test` on every pull request.
