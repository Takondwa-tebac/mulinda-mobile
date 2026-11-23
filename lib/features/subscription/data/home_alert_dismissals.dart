import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/providers/auth_controller.dart';
import 'subscription_models.dart';

/// How far the user has put a Home alert away, stored per user and per
/// trial or pass on this phone.
enum AlertDismissal {
  /// Never closed.
  none,

  /// Closed while more than [trialFinalStretchHours] of the trial were left:
  /// it comes back once for the final stretch.
  early,

  /// Closed for good (for this trial or pass).
  done,
}

/// The trial banner comes back once when this many hours or fewer are left.
const trialFinalStretchHours = 48;

String trialBannerDismissedKey(String userId, DateTime endsAt) =>
    'trial_banner_dismissed_${userId}_${endsAt.toUtc().toIso8601String()}';

String topUpCardDismissedKey(String userId, DateTime endsAt) =>
    'top_up_card_dismissed_${userId}_${endsAt.toUtc().toIso8601String()}';

/// The trial banner is shown unless closed, or closed early and the final
/// [trialFinalStretchHours] have not started yet.
bool trialBannerVisible({required int hoursLeft, required AlertDismissal dismissal}) => switch (dismissal) {
  AlertDismissal.none => true,
  AlertDismissal.early => hoursLeft <= trialFinalStretchHours,
  AlertDismissal.done => false,
};

/// What closing the trial banner now records: early while the final stretch
/// has not started (so it returns once), otherwise for good.
AlertDismissal trialDismissalFor(int hoursLeft, AlertDismissal current) =>
    hoursLeft > trialFinalStretchHours && current == AlertDismissal.none ? AlertDismissal.early : AlertDismissal.done;

/// The stored dismissal under a prefs key. `null` while loading; an
/// unreadable store counts as never closed.
class AlertDismissalController extends FamilyNotifier<AlertDismissal?, String> {
  @override
  AlertDismissal? build(String key) {
    _load(key);
    return null;
  }

  Future<void> _load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(key) ?? 0;
      if (state == null) {
        state = AlertDismissal.values[stored.clamp(0, AlertDismissal.values.length - 1)];
      }
    } catch (_) {
      if (state == null) state = AlertDismissal.none;
    }
  }

  Future<void> set(AlertDismissal value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(arg, value.index);
    } catch (_) {}
  }
}

final alertDismissalProvider = NotifierProvider.family<AlertDismissalController, AlertDismissal?, String>(
  AlertDismissalController.new,
);

/// Helper for widgets: the key for [sub] and the signed-in user, built by [make].
String? alertKeyFor(WidgetRef ref, SubscriptionInfo sub, String Function(String, DateTime) make) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  final ends = sub.endsAt;
  if (userId == null || ends == null) return null;
  return make(userId, ends);
}
