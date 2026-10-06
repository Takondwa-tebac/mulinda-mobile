import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:path_provider/path_provider.dart';
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

  /// Show a notification now (used to surface foreground FCM messages). When
  /// [imageUrl] is given the image is downloaded and shown as a big picture;
  /// if the download fails the plain notification is still shown.
  static Future<void> show(String title, String body, {String? imageUrl}) async {
    try {
      final imagePath = await _downloadImage(imageUrl);
      final style = imagePath == null
          ? null
          : BigPictureStyleInformation(
              FilePathAndroidBitmap(imagePath),
              hideExpandedLargeIcon: true,
              contentTitle: title,
              summaryText: body,
            );
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
            styleInformation: style,
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<String?> _downloadImage(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/push_${url.hashCode}.img';
      await Dio().download(
        url,
        path,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }
}
