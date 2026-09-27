# Morning Wave

A daily check-in for parents who live alone, so their grown children can stay
in touch. Flutter app, Android only for now.

## Run it

```sh
flutter pub get
flutter run --dart-define-from-file=config/dev.json
```

The app starts without any config: Supabase, push and crash reporting just
stay off and a line in the debug log says so.

## Config you fill in (never committed)

| File | What goes in it | Where to get it |
| --- | --- | --- |
| `config/dev.json` | Copy `config/example.json`, set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` | Supabase dashboard, Project Settings > API Keys |
| `android/app/google-services.json` | Firebase Android config for package `app.morningwave` | Firebase console, Project settings > Your apps > Add Android app |

Both paths are in `.gitignore`. When `google-services.json` is present the
Google Services and Crashlytics Gradle plugins switch on automatically.

## What is wired

- `supabase_flutter`, initialised from `config/*.json` via `--dart-define-from-file`.
- `firebase_core`, `firebase_messaging`, `firebase_crashlytics` (Flutter and
  async errors go to Crashlytics).
- `flutter_local_notifications` with an `urgent` channel (max importance).
  Server pushes for missed check-ins should set `android.notification.channel_id`
  to `urgent`.
- Android 13+ notification permission is requested on the home screen.
- `google_sign_in` is added but not used yet.

## Checks

CI (`.github/workflows/app.yml`) runs `dart format`, `flutter analyze` and
`flutter test` on every pull request.
