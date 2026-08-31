import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

  /// Fixed id for the "review your transactions" reminder so re-scheduling
  /// replaces the previous one rather than stacking duplicates.
  static const int reviewReminderId = 42001;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      // The app is Malawi-first; align reminders to local end-of-day there.
      tz.setLocalLocation(tz.getLocation('Africa/Blantyre'));

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

  /// Ask for the OS permissions a scheduled reminder needs: notifications
  /// (Android 13+/iOS) and exact alarms (Android 12+). Returns true if a
  /// reminder can be posted at all (notifications granted).
  static Future<bool> requestReminderPermissions() async {
    try {
      final notif = await Permission.notification.request();
      // Exact-alarm is best-effort — a denied one downgrades to an inexact
      // reminder rather than failing.
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
      return notif.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canScheduleExact() async {
    try {
      return await Permission.scheduleExactAlarm.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Schedule a one-off reminder to review auto-recorded transactions. Falls
  /// back to an inexact alarm when exact-alarm permission isn't granted.
  static Future<void> scheduleReviewReminder(DateTime when, {String? body}) async {
    try {
      final exact = await canScheduleExact();
      await _plugin.zonedSchedule(
        reviewReminderId,
        'Review your transactions',
        body ?? 'You have auto-recorded transactions waiting to be checked.',
        tz.TZDateTime.from(when, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Scheduling unavailable — ignore rather than crash the caller.
    }
  }

  static Future<void> cancelReviewReminder() async {
    try {
      await _plugin.cancel(reviewReminderId);
    } catch (_) {}
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
