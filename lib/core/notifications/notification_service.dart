import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local-notifications setup. Initialises the plugin and a reminders channel so
/// bill / loan-repayment reminders can be surfaced. Best-effort: never throws.
///
/// NOTE: server-generated reminders currently surface in-app via the Insights
/// screen. True background/push delivery needs FCM — a future addition; this
/// scaffold makes local scheduling available in the meantime.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'mulinda_reminders',
    'Reminders',
    description: 'Bill and loan-repayment reminders',
    importance: Importance.high,
  );

  static Future<void> init() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));

      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    } catch (_) {
      // Plugin unavailable (e.g. unsupported platform) — ignore.
    }
  }

  /// Show a notification now (used to surface foreground FCM messages).
  static Future<void> show(String title, String body) async {
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }
}
