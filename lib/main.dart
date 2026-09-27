import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  } else {
    debugPrint('Supabase disabled: no config passed (see README).');
  }
  await Notifications.init();
  runApp(const MorningWaveApp());
}

/// Firebase reads android/app/google-services.json, which is not committed.
/// Without it the app runs with push and crash reporting off.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } on Exception catch (e) {
    debugPrint('Firebase disabled: $e');
    return;
  }
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

class MorningWaveApp extends StatelessWidget {
  const MorningWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morning Wave',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
      ),
      home: const HomeScreen(
        requestNotificationPermission: Notifications.requestPermission,
      ),
    );
  }
}
