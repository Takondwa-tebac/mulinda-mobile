import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/clock.dart';
import '../../auth/providers/auth_controller.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/data/dashboard_repository.dart';

/// For this long after sign-up, Plan keeps to budgets and goals.
const earlyPlanDays = 14;

/// After the early period, how long Home may still offer "More on your Plan"
/// (so people who signed up long ago never see "two weeks" copy).
const moreOnPlanOfferDays = 30;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The day loans, investments and projects appear on their own: day 14 of the
/// account (the sign-up day plus [earlyPlanDays]), as a local date.
DateTime planToolsUnlockDay(DateTime createdAt) {
  final start = _day(createdAt.toLocal());
  return DateTime(start.year, start.month, start.day + earlyPlanDays);
}

/// The account is in its first [earlyPlanDays] days. Unknown age is not early.
bool isEarlyAccount(DateTime? createdAt, DateTime now) =>
    createdAt != null && _day(now).isBefore(planToolsUnlockDay(createdAt));

/// The user already has a loan, an investment or a project.
bool hasCommitments(DashboardSummary d) =>
    d.loansActive > 0 ||
    d.loansOutstanding.minorUnits != 0 ||
    d.investmentsCount > 0 ||
    d.investmentsValue.minorUnits != 0 ||
    d.projectsActive > 0;

/// What Home and Plan show of loans, investments and projects.
@immutable
class PlanToolsGate {
  const PlanToolsGate({this.hideCommitments = false, this.showMoreOnPlan = false, this.unlockDay});

  /// Everything is shown.
  static const open = PlanToolsGate();

  /// Leave out the Loans and Investments figures on Home and the Commitments
  /// rows on Plan; Plan shows "More tools from `unlockDay`" instead.
  final bool hideCommitments;

  /// Show "More on your Plan" on Home (once: either button dismisses it).
  final bool showMoreOnPlan;

  /// Day 14 of the account, when known.
  final DateTime? unlockDay;
}

/// The rules for the first two weeks:
/// - early (under 14 days old), nothing unlocked and no loan, investment or
///   project yet: commitments are hidden;
/// - anyone who has one sees everything from day 1;
/// - from day 14, unless unlocked early or already dismissed, Home offers
///   "More on your Plan" once (within [moreOnPlanOfferDays]);
/// - no sign-up date (older server or cached user): everything is shown.
///
/// [hasCommitments] is null while the dashboard is not loaded yet.
PlanToolsGate planToolsGate({
  required DateTime? createdAt,
  required DateTime now,
  required bool? hasCommitments,
  required bool unlocked,
  required bool moreOnPlanDone,
}) {
  if (createdAt == null) return PlanToolsGate.open;
  final unlockDay = planToolsUnlockDay(createdAt);
  final today = _day(now);
  if (today.isBefore(unlockDay)) {
    return PlanToolsGate(hideCommitments: !unlocked && hasCommitments != true, unlockDay: unlockDay);
  }
  final offerEnds = DateTime(unlockDay.year, unlockDay.month, unlockDay.day + moreOnPlanOfferDays);
  return PlanToolsGate(
    showMoreOnPlan: !unlocked && !moreOnPlanDone && hasCommitments == false && today.isBefore(offerEnds),
    unlockDay: unlockDay,
  );
}

/// What this user chose on this phone: tools shown early, and whether
/// "More on your Plan" was dealt with.
@immutable
class PlanToolsPrefs {
  const PlanToolsPrefs({this.loaded = false, this.unlocked = false, this.moreOnPlanDone = false});

  final bool loaded;
  final bool unlocked;
  final bool moreOnPlanDone;
}

String planToolsUnlockedKey(String userId) => 'plan_tools_unlocked_$userId';
String moreOnPlanDoneKey(String userId) => 'plan_more_card_done_$userId';

class PlanToolsController extends Notifier<PlanToolsPrefs> {
  String? _userId;

  @override
  PlanToolsPrefs build() {
    _userId = ref.watch(currentUserProvider.select((u) => u?.id));
    final id = _userId;
    if (id != null) _load(id);
    return const PlanToolsPrefs();
  }

  Future<void> _load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_userId != userId) return;
      state = PlanToolsPrefs(
        loaded: true,
        unlocked: prefs.getBool(planToolsUnlockedKey(userId)) ?? false,
        moreOnPlanDone: prefs.getBool(moreOnPlanDoneKey(userId)) ?? false,
      );
    } catch (_) {
      // Unreadable: nothing chosen yet, but the card is not offered.
      if (_userId == userId) state = const PlanToolsPrefs(loaded: true, moreOnPlanDone: true);
    }
  }

  /// "Show them now": loans, investments and projects for good.
  Future<void> unlock() async {
    state = PlanToolsPrefs(loaded: true, unlocked: true, moreOnPlanDone: state.moreOnPlanDone);
    await _save(planToolsUnlockedKey);
  }

  /// "Open Plan" or "Not now" on "More on your Plan".
  Future<void> dismissMoreOnPlan() async {
    state = PlanToolsPrefs(loaded: true, unlocked: state.unlocked, moreOnPlanDone: true);
    await _save(moreOnPlanDoneKey);
  }

  Future<void> _save(String Function(String) key) async {
    final id = _userId;
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key(id), true);
    } catch (_) {}
  }
}

final planToolsPrefsProvider = NotifierProvider<PlanToolsController, PlanToolsPrefs>(PlanToolsController.new);

/// The gate for the signed-in user, from the dashboard already loaded for
/// Home and Plan.
final planToolsGateProvider = Provider.autoDispose<PlanToolsGate>((ref) {
  final createdAt = ref.watch(currentUserProvider.select((u) => u?.createdAt));
  if (createdAt == null) return PlanToolsGate.open;
  final dashboard = ref.watch(dashboardProvider).valueOrNull;
  final prefs = ref.watch(planToolsPrefsProvider);
  final gate = planToolsGate(
    createdAt: createdAt,
    now: ref.read(clockProvider)(),
    hasCommitments: dashboard == null ? null : hasCommitments(dashboard),
    unlocked: prefs.unlocked,
    // Not offered until the stored choice is known.
    moreOnPlanDone: prefs.moreOnPlanDone || !prefs.loaded,
  );
  return gate;
});
