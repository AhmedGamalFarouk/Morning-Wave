/// Build-time settings, passed with `--dart-define-from-file=config/dev.json`.
///
/// Nothing here is committed; see `config/example.json` and the README.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Which home screen to preview; see HomeScreen.
  static const preview = String.fromEnvironment('PREVIEW');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
