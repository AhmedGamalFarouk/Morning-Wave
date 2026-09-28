/// Build-time settings, passed with `--dart-define-from-file=config/dev.json`.
///
/// Nothing here is committed; see `config/example.json` and the README.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// The Web OAuth client ID from Google Cloud. Android sign-in asks
  /// Google for an ID token issued to this client, which Supabase checks.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// Which home screen to preview; see HomeScreen.
  static const preview = String.fromEnvironment('PREVIEW');

  /// RevenueCat's public Android API key for the family plan.
  static const revenueCatApiKey = String.fromEnvironment('REVENUECAT_API_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static bool get hasRevenueCat => revenueCatApiKey.isNotEmpty;
}
