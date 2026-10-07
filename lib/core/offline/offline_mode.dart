import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/subscription/data/subscription_models.dart';
import 'cache_store.dart';
import 'offline_prefetch.dart';
import 'prefs.dart';
import 'trusted_clock.dart';

/// Whether offline mode is available to this user and whether they turned it on.
class OfflineModeState {
  const OfflineModeState({
    required this.eligible,
    required this.enabled,
    this.until,
    this.clockWrong = false,
  });

  /// The phone's clock is earlier than a time the app has already seen, so
  /// offline mode is paused until it next reaches the server.
  final bool clockWrong;

  /// The plan grants offline mode and it has not expired (3-day, weekly,
  /// monthly or trial — never Day Pass).
  final bool eligible;

  /// The user's own choice (off by default, stored per account on this device).
  final bool enabled;

  /// When offline-mode access ends, if known.
  final DateTime? until;

  /// Offline mode is actually in effect.
  bool get active => eligible && enabled;

  /// The user turned it on but their plan no longer includes it.
  bool get paused => enabled && !eligible;

  OfflineModeState copyWith({bool? enabled}) =>
      OfflineModeState(eligible: eligible, enabled: enabled ?? this.enabled, until: until, clockWrong: clockWrong);
}

/// Source of truth for offline mode. Eligibility comes from the plan that the
/// API reports (remembered on the device, so it can be evaluated with no
/// connection); the on/off switch is a local per-account preference.
class OfflineModeController extends Notifier<OfflineModeState> {
  static String _key(String userId) => offlineModePrefKey(userId);

  @override
  OfflineModeState build() {
    final user = ref.watch(currentUserProvider);
    final info = user?.subscription;
    final until = info?.offlineModeUntil;
    final prefs = ref.read(sharedPreferencesProvider);
    final clockWrong = TrustedClock.looksTampered(prefs);
    final eligible = user != null &&
        (info?.can(Entitlements.offlineMode) ?? false) &&
        (until == null || until.isAfter(DateTime.now())) &&
        !clockWrong;

    // Read synchronously (preferences are loaded before the first frame) so the
    // very first requests already know whether offline mode is on.
    final enabled = user != null && (prefs.getBool(_key(user.id)) ?? false);
    return OfflineModeState(eligible: eligible, enabled: enabled, until: until, clockWrong: clockWrong);
  }

  /// Turn offline mode on or off. Turning it on is refused unless the plan
  /// includes it; turning it off is always allowed.
  Future<void> setEnabled(bool value) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (value && !state.eligible) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_key(user.id), value);
    state = state.copyWith(enabled: value);
    // Turning it on saves the main screens' data straight away, so going offline
    // right after finds something to show.
    if (value) {
      unawaited(ref.read(offlinePrefetchProvider.notifier).start(force: true));
    }
    // Turning it off removes everything saved on the phone for this account.
    if (!value) {
      await prefs.remove(OfflinePrefetcher.lastKey);
      await prefs.remove(OfflinePrefetcher.cursorKey);
      try {
        await EncryptedCacheStore.instance.clearUser(user.id);
      } catch (_) {}
    }
  }
}

final offlineModeProvider =
    NotifierProvider<OfflineModeController, OfflineModeState>(OfflineModeController.new);
