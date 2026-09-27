import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notification setup: the channels the app posts to and the
/// Android 13+ runtime permission.
class Notifications {
  /// For missed check-ins. Server pushes set `channel_id: "urgent"`.
  static const urgentChannel = AndroidNotificationChannel(
    'urgent',
    'Urgent',
    description: 'A missed check-in or anything that needs you now.',
    importance: Importance.max,
  );

  static final _plugin = FlutterLocalNotificationsPlugin();

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _android?.createNotificationChannel(urgentChannel);
  }

  /// Shows the system prompt on Android 13+. Returns true if allowed.
  static Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;
}
