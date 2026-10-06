import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/providers/auth_controller.dart';

/// Whether screenshots and screen recording are blocked in the app.
///
/// Blocked for everyone by default. Only a super-admin can switch it off, and
/// the choice is stored per account on this device, so it never affects
/// other users who sign in on the same phone. State is `true` while protected.
class ScreenshotProtection extends Notifier<bool> {
  static String _key(String userId) => 'screenshots_allowed_$userId';

  @override
  bool build() {
    final user = ref.watch(currentUserProvider);
    if (user != null && user.isSuperAdmin) _load(user.id);
    // Secure by default until the stored choice is read.
    return true;
  }

  Future<void> _load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    state = !(prefs.getBool(_key(userId)) ?? false);
  }

  /// Turn protection on/off for the signed-in super-admin. Ignored for anyone else.
  Future<void> setProtected(bool value) async {
    final user = ref.read(currentUserProvider);
    if (user == null || !user.isSuperAdmin) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(user.id), !value);
    state = value;
  }
}

final screenshotProtectionProvider =
    NotifierProvider<ScreenshotProtection, bool>(ScreenshotProtection.new);

/// Applies the protection to the whole app window (Android `FLAG_SECURE`,
/// which blocks screenshots and screen recording and blanks the recents
/// preview). Wraps the app without touching it, so toggling never rebuilds the
/// Navigator. No-op on platforms without the native channel.
class ScreenshotGuard extends ConsumerStatefulWidget {
  const ScreenshotGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ScreenshotGuard> createState() => _ScreenshotGuardState();
}

class _ScreenshotGuardState extends ConsumerState<ScreenshotGuard> {
  static const _channel = MethodChannel('mulinda/screen_security');

  ProviderSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual<bool>(
      screenshotProtectionProvider,
      (_, isProtected) => _apply(isProtected),
      fireImmediately: true,
    );
  }

  Future<void> _apply(bool isProtected) async {
    try {
      await _channel.invokeMethod('setSecure', {'secure': isProtected});
    } on MissingPluginException {
      // Not Android (iOS/desktop/tests) — nothing to do.
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
