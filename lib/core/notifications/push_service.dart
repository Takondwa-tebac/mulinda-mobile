import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/insights/data/insights_repository.dart';
import '../../features/capture/data/inbox_repository.dart';
import '../network/dio_client.dart';
import '../router/app_router.dart';
import '../router/routes.dart';
import 'notification_service.dart';

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

      // Foreground: show local notification and refresh the relevant provider.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) NotificationService.show(n.title ?? 'Mulinda', n.body ?? '');
        _refreshFromData(ref, m.data);
      });

      // Background tap: route to the correct screen.
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _navigate(ref, m.data));

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

  Future<void> _registerToken(WidgetRef ref, String token) async {
    try {
      await ref.read(dioProvider).post('/v1/devices', data: {'token': token, 'platform': 'android'});
    } catch (_) {}
  }

  /// Invalidate the appropriate Riverpod provider so the UI refreshes
  /// immediately when a foreground push arrives.
  void _refreshFromData(WidgetRef ref, Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'inbox') {
      ref.invalidate(pendingSmsProvider);
      ref.invalidate(pendingReceiptsProvider);
    } else {
      ref.invalidate(unreadInsightsCountProvider);
    }
  }

  /// Navigate to the correct screen based on the notification data payload.
  void _navigate(WidgetRef ref, Map<String, dynamic> data) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final type = data['type'] as String?;
      final itemType = data['item_type'] as String?;
      final router = ref.read(routerProvider);
      if (type == 'daily_summary') {
        router.go(Routes.dailySummaries);
      } else if (type == 'export') {
        router.go(Routes.exports);
      } else if (type == 'inbox' && itemType == 'transaction') {
        // Auto-recorded SMS transactions land in the review queue.
        router.go(Routes.review);
      } else if (type == 'inbox') {
        router.go(Routes.inbox);
      } else {
        router.go(Routes.insights);
      }
    });
  }
}
