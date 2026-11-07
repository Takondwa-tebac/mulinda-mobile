import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/insights/data/insights_repository.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/capture/data/inbox_repository.dart';
import '../../features/subscription/data/subscription_repository.dart';
import '../network/dio_client.dart';
import '../router/routes.dart';
import 'in_app_banner.dart';
import 'notification_router.dart';

/// Firebase Cloud Messaging: foreground display, tap-to-open, and device-token
/// registration (which happens once the user is authenticated, since the
/// /v1/devices endpoint is protected).
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _wired = false;

  /// Wire message listeners once. Best-effort — never throws.
  Future<void> init(WidgetRef ref) async {
    if (_wired) return;
    _wired = true;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();

      // Foreground: Android shows no system notification for an FCM message
      // while the app is open, so show an in-app banner (not a second, local
      // notification) with "View", and refresh the relevant data.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        final title = n?.title ?? m.data['title']?.toString();
        if (title != null && title.isNotEmpty) {
          showPushBanner(
            title: title,
            body: n?.body ?? m.data['body']?.toString(),
            onView: () => NotificationRouter.instance.open(ref, m.data),
          );
        }
        _refreshFromData(ref, m.data);
      });

      // Background tap: route to the correct screen.
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _navigate(ref, m.data),
      );

      // Cold-start tap.
      final initial = await fm.getInitialMessage();
      if (initial != null) _navigate(ref, initial.data);

      fm.onTokenRefresh.listen((t) => _registerToken(ref, t));
    } catch (_) {
      // FCM unavailable (no Google Play services / unsupported platform).
    }
  }

  /// Register this device's FCM token with the backend. Call when authenticated.
  Future<void> registerToken(WidgetRef ref) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(ref, token);
    } catch (_) {}
  }

  /// Invalidate this device's FCM token on sign-out so pushes meant for the
  /// previous account can never reach it; a fresh token is issued on next login.
  Future<void> unregister() async {
    // Nothing opened from a notification may carry over to the next account.
    NotificationRouter.instance.clear();
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> _registerToken(WidgetRef ref, String token) async {
    try {
      await ref
          .read(dioProvider)
          .post('/v1/devices', data: {'token': token, 'platform': 'android'});
    } catch (_) {}
  }

  /// Invalidate the appropriate Riverpod provider so the UI refreshes
  /// immediately when a foreground push arrives.
  void _refreshFromData(WidgetRef ref, Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'inbox') {
      ref.invalidate(pendingSmsProvider);
      ref.invalidate(pendingReceiptsProvider);
    } else if (isSubscriptionPushType(type)) {
      // A plan switched on, a payment failed, or access is ending: reload the
      // plan and entitlements, and the invoice list.
      ref.read(authControllerProvider.notifier).refresh();
      ref.invalidate(invoicesProvider);
    } else {
      ref.invalidate(unreadInsightsCountProvider);
      ref.invalidate(insightsProvider);
    }
  }

  /// Open the notification's screen (see NotificationRouter): now when the
  /// user is in the app, after sign-in otherwise.
  void _navigate(WidgetRef ref, Map<String, dynamic> data) {
    WidgetsBinding.instance.addPostFrameCallback((_) => NotificationRouter.instance.open(ref, data));
  }
}

/// Push types that open the Subscription screen.
bool isSubscriptionPushType(String? type) => subscriptionPushTypes.contains(type);

/// Where the `audit_export_ready` push opens: the audit trail showing that export.
String auditExportLocation(String? exportId) => exportId == null || exportId.isEmpty
    ? Routes.adminAudit
    : '${Routes.adminAudit}?export=${Uri.encodeQueryComponent(exportId)}';
