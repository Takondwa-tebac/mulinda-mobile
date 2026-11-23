import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/admin/data/admin_repository.dart';
import '../../features/auth/providers/auth_controller.dart';

/// Whether screenshots and screen recording are blocked in the app.
///
/// Blocked for everyone by default. A super-admin can allow it for any
/// account (admin User Details, or Profile for their own). The setting lives
/// on the server, so it follows the account to every phone and never affects
/// other people who sign in on the same phone. The app picks up a change when
/// it next loads the profile (on start and on returning to the app). State
/// is `true` while protected.
class ScreenshotProtection extends Notifier<bool> {
  @override
  bool build() => !(ref.watch(currentUserProvider)?.screenshotsAllowed ?? false);

  /// The signed-in super-admin's own switch in Profile: the same server
  /// setting as their row in User Details. Ignored for anyone else. Applied
  /// at once; put back if the server refuses.
  Future<void> setProtected(bool value) async {
    final user = ref.read(currentUserProvider);
    if (user == null || !user.isSuperAdmin) return;
    state = value;
    try {
      await ref.read(adminRepositoryProvider).setScreenshotsAllowed(user.id, allowed: !value);
      await ref.read(authControllerProvider.notifier).refresh();
    } catch (_) {
      state = !(ref.read(currentUserProvider)?.screenshotsAllowed ?? false);
      rethrow;
    }
  }
}

final screenshotProtectionProvider =
    NotifierProvider<ScreenshotProtection, bool>(ScreenshotProtection.new);

/// Screens that allow screenshots while they are open (the referral screen,
/// so people can screenshot their QR code). A count, so two such screens on
/// the stack do not switch protection back on when only one of them closes.
/// Use [ScreenshotsAllowed] rather than calling this directly.
class ScreenshotExemptions extends Notifier<int> {
  @override
  int build() => 0;

  void acquire() => state = state + 1;

  void release() {
    if (state > 0) state = state - 1;
  }
}

final screenshotExemptionsProvider =
    NotifierProvider<ScreenshotExemptions, int>(ScreenshotExemptions.new);

/// What is applied to the window: the account setting, lifted while a screen
/// that allows screenshots is open.
bool effectiveScreenshotProtection({required bool protectedSetting, required int exemptions}) =>
    protectedSetting && exemptions == 0;

final effectiveScreenshotProtectionProvider = Provider<bool>(
  (ref) => effectiveScreenshotProtection(
    protectedSetting: ref.watch(screenshotProtectionProvider),
    exemptions: ref.watch(screenshotExemptionsProvider),
  ),
);

/// Allows screenshots while [child] is in the tree, and restores the
/// protection when it leaves. Only for screens with nothing sensitive on them.
class ScreenshotsAllowed extends ConsumerStatefulWidget {
  const ScreenshotsAllowed({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ScreenshotsAllowed> createState() => _ScreenshotsAllowedState();
}

class _ScreenshotsAllowedState extends ConsumerState<ScreenshotsAllowed> {
  late final ScreenshotExemptions _exemptions;
  bool _acquired = false;

  @override
  void initState() {
    super.initState();
    _exemptions = ref.read(screenshotExemptionsProvider.notifier);
    // Providers cannot change while the tree is building.
    Future.microtask(() {
      if (!mounted) return;
      _exemptions.acquire();
      _acquired = true;
    });
  }

  @override
  void dispose() {
    if (_acquired) {
      Future.microtask(() {
        try {
          _exemptions.release();
        } catch (_) {
          // The app (and its providers) closed at the same time.
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Applies the protection (see [effectiveScreenshotProtectionProvider]) to the
/// whole app window (Android `FLAG_SECURE`, which blocks screenshots and screen recording and blanks the recents
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
      effectiveScreenshotProtectionProvider,
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
