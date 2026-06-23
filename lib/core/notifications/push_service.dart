import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/insights/data/insights_repository.dart';
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

      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) NotificationService.show(n.title ?? 'Mulinda', n.body ?? '');
        ref.invalidate(unreadInsightsCountProvider);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) => _openInsights(ref));

      final initial = await fm.getInitialMessage();
      if (initial != null) _openInsights(ref);

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
    } catch (_) {
      // Not signed in yet or endpoint unavailable — will retry on next auth/refresh.
    }
  }

  void _openInsights(WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(routerProvider).go(Routes.insights));
  }
}
