import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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

  /// For everyday nudges, like the parent's reminder to say good morning.
  /// Server pushes set `channel_id: "gentle"`. Normal importance: it sounds,
  /// but never pops over what the parent is doing.
  static const gentleChannel = AndroidNotificationChannel(
    'gentle',
    'Good morning notes',
    description: 'Little reminders and notes from your family.',
    importance: Importance.defaultImportance,
  );

  /// Every channel [init] creates, by id.
  static final _channels = {
    urgentChannel.id: urgentChannel,
    gentleChannel.id: gentleChannel,
  };

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
    for (final channel in _channels.values) {
      await _android?.createNotificationChannel(channel);
    }
  }

  /// Shows the system prompt on Android 13+. Returns true if allowed.
  static Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  /// Whether notifications are already allowed, so the app doesn't ask again.
  static Future<bool> areEnabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  /// This install's push token, or null when Firebase isn't set up.
  static Future<String?> currentToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('Reading the push token: $error');
      return null;
    }
  }

  /// Fires when Firebase issues a new token for this install (a reinstall,
  /// a cleared app, or a routine rotation), so it can be saved again.
  static Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  /// Android only shows FCM notifications itself while the app is in the
  /// background, so foreground ones are posted here.
  static Future<void> showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    // Use the channel the server picked, so quiet messages stay quiet.
    // Anything unrecognised goes out gently rather than as an alarm.
    final channel = _channels[notification.android?.channelId] ?? gentleChannel;
    final body = notification.body;
    await _plugin.show(
      id: notification.hashCode,
      title: notification.title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          // Android 7 ignores channels and reads priority instead.
          priority: channel.importance.value >= Importance.high.value
              ? Priority.high
              : Priority.defaultPriority,
          // Collapsed, this still reads as one line; a pulled-down tap
          // expands to the full note, so nothing is ever cut off.
          styleInformation: body == null
              ? null
              : BigTextStyleInformation(
                  body,
                  contentTitle: notification.title,
                ),
        ),
      ),
    );
  }
}
