import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notification setup: the channels the app posts to and the
/// Android 13+ runtime permission.
class Notifications {
  /// For messages that shouldn't wait, like a missed check-in. Server pushes
  /// set `channel_id: "urgent"`. The name shows in Android settings, where a
  /// parent may read it, so it stays warm.
  static const urgentChannel = AndroidNotificationChannel(
    'urgent',
    'Family messages',
    description: 'Messages from your family that shouldn\'t wait.',
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

  /// Android only shows FCM notifications itself while the app is in the
  /// background, so foreground ones are posted here.
  static Future<void> showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _plugin.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          urgentChannel.id,
          urgentChannel.name,
          channelDescription: urgentChannel.description,
          importance: urgentChannel.importance,
          priority: Priority.high,
        ),
      ),
    );
  }
}
