import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'family/auth.dart';
import 'family/family_repository.dart';
import 'screens/app_gate.dart';
import 'screens/home_screen.dart';
import 'services/notifications.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  if (await _initFirebase()) {
    FirebaseMessaging.onMessage.listen(Notifications.showForeground);
  }
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  } else {
    debugPrint('Supabase disabled: no config passed (see README).');
  }
  runApp(const MorningWaveApp());
}

/// Firebase reads android/app/google-services.json, which is not committed.
/// Without it a debug build runs with push and crash reporting off; release
/// builds refuse to build without it (android/app/build.gradle.kts).
Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (error, stack) {
    debugPrint('Firebase disabled, push and Crashlytics are off: $error');
    debugPrintStack(stackTrace: stack);
    return false;
  }
  final crashlytics = FirebaseCrashlytics.instance;
  // Keep dev crashes out of the dashboard watched during testing.
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = crashlytics.recordFlutterError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
  return true;
}

class MorningWaveApp extends StatelessWidget {
  const MorningWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morning Wave',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Without Supabase config, a debug build previews the home screens.
      home: AppConfig.hasSupabase
          ? _signedInApp()
          : HomeScreen(
              requestNotificationPermission: Notifications.requestPermission,
              notificationsEnabled: Notifications.areEnabled,
              preview: parseHomePreview(AppConfig.preview),
            ),
    );
  }
}

Widget _signedInApp() {
  final client = Supabase.instance.client;
  final auth = SupabaseAuth(client.auth);
  return AppGate(
    auth: auth,
    families: SupabaseFamilyRepository(
      client,
      childName: () => auth.childFirstName,
    ),
    requestNotificationPermission: Notifications.requestPermission,
    notificationsEnabled: Notifications.areEnabled,
  );
}
