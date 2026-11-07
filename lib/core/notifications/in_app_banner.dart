import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The app's root ScaffoldMessenger (set on MaterialApp.router), so a push
/// that arrives while the app is open can show a banner over any screen.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

int _bannerToken = 0;

/// Shows a push that arrived while the app is open as an in-app banner at the
/// top, with "View" (opens it) and "Dismiss". It goes away by itself after
/// [duration]. Nothing is shown as a system notification as well.
void showPushBanner({
  required String title,
  String? body,
  required VoidCallback onView,
  Duration duration = const Duration(seconds: 6),
  ScaffoldMessengerState? messenger,
}) {
  final m = messenger ?? rootMessengerKey.currentState;
  if (m == null) return;
  final token = ++_bannerToken;
  m
    ..hideCurrentMaterialBanner()
    ..showMaterialBanner(
      MaterialBanner(
        key: const ValueKey('push-banner'),
        leading: const Icon(Icons.notifications_active_outlined),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (body != null && body.isNotEmpty) Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton(onPressed: m.hideCurrentMaterialBanner, child: Text('notifications2.dismiss'.tr())),
          TextButton(
            key: const ValueKey('push-banner-view'),
            onPressed: () {
              m.hideCurrentMaterialBanner();
              onView();
            },
            child: Text('notifications2.view'.tr()),
          ),
        ],
      ),
    );
  Timer(duration, () {
    if (token == _bannerToken) m.hideCurrentMaterialBanner();
  });
}
