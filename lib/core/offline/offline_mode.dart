import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/subscription/data/subscription_models.dart';

/// Whether offline mode is available to this user and whether they turned it on.
class OfflineModeState {
  const OfflineModeState({
    required this.eligible,
    required this.enabled,
    this.until,
  });

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
      OfflineModeState(eligible: eligible, enabled: enabled ?? this.enabled, until: until);
}

/// Source of truth for offline mode. Eligibility comes from the plan that the
/// API reports (remembered on the device, so it can be evaluated with no
/// connection); the on/off switch is a local per-account preference.
class OfflineModeController extends Notifier<OfflineModeState> {
  static String _key(String userId) => 'offline_mode_enabled_$userId';

  @override
  OfflineModeState build() {
    final user = ref.watch(currentUserProvider);
    final info = user?.subscription;
    final until = info?.offlineModeUntil;
    final eligible = user != null &&
        (info?.can(Entitlements.offlineMode) ?? false) &&
        (until == null || until.isAfter(DateTime.now()));

    if (user != null) _load(user.id);
    return OfflineModeState(eligible: eligible, enabled: false, until: until);
  }

  Future<void> _load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(enabled: prefs.getBool(_key(userId)) ?? false);
  }

  /// Turn offline mode on or off. Turning it on is refused unless the plan
  /// includes it; turning it off is always allowed.
  Future<void> setEnabled(bool value) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (value && !state.eligible) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(user.id), value);
    state = state.copyWith(enabled: value);
  }
}

final offlineModeProvider =
    NotifierProvider<OfflineModeController, OfflineModeState>(OfflineModeController.new);
