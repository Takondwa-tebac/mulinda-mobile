import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/data/activity_feed.dart';
import '../../features/activity/data/activity_models.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/insights/data/insights_repository.dart';
import '../router/app_router.dart';
import '../router/routes.dart';

/// Where a notification leads.
class NotificationDestination {
  const NotificationDestination(this.location, {this.tab = false, this.activityFilter});

  /// A router location (path plus any query).
  final String location;

  /// A bottom-tab destination: switch to it (`go`) instead of pushing on top.
  final bool tab;

  /// Filters to apply when the destination is Activity.
  final TxnQuery? activityFilter;

  @override
  String toString() => 'NotificationDestination($location, tab: $tab, filter: $activityFilter)';
}

String? _str(dynamic v) => (v == null || v.toString().isEmpty || v.toString() == 'null') ? null : v.toString();

DateTime? _day(dynamic v) {
  final s = _str(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Activity filters from push `params` (flat in FCM data, an object in the
/// notification list): category_id, from, to (YYYY-MM-DD), tx_type.
TxnQuery activityQueryFrom(Map<String, dynamic> data) {
  final params = data['params'] is Map ? (data['params'] as Map).cast<String, dynamic>() : data;
  final type = _str(params['tx_type'] ?? params['type_filter']);
  return TxnQuery(
    categoryId: _str(params['category_id']),
    from: _day(params['from'] ?? params['period_start']),
    to: _day(params['to'] ?? params['period_end']),
    type: type == 'income' || type == 'expense' ? type : null,
  );
}

/// Maps push or notification data to a screen. Uses `target`/`target_id`
/// (round-3 API) and falls back to the older `type` keys for older servers.
NotificationDestination destinationFor(Map<String, dynamic> data) {
  final target = _str(data['target']);
  final id = _str(data['target_id']);
  if (target != null) {
    final byTarget = _byTarget(target, id, data);
    if (byTarget != null) return byTarget;
  }
  return _byType(data);
}

NotificationDestination? _byTarget(String target, String? id, Map<String, dynamic> data) => switch (target) {
  'budget' => NotificationDestination(id == null ? Routes.budgets : Routes.budgetById(id)),
  'loan' => NotificationDestination(id == null ? Routes.loans : Routes.loanById(id)),
  'goal' => NotificationDestination(id == null ? Routes.goals : Routes.goalById(id)),
  'investment' => NotificationDestination(id == null ? Routes.investments : Routes.investmentById(id)),
  'bill' =>
    id == null ? const NotificationDestination(Routes.plan, tab: true) : NotificationDestination(Routes.billById(id)),
  'daily_summary' => NotificationDestination(id == null ? Routes.dailySummaries : Routes.dailySummaryById(id)),
  'transaction' =>
    id == null
        ? const NotificationDestination(Routes.activity, tab: true)
        : NotificationDestination(Routes.transactionById(id)),
  'review' => NotificationDestination(
    id == null ? Routes.review : '${Routes.review}?highlight=${Uri.encodeQueryComponent(id)}',
  ),
  'inbox_sms' || 'inbox_receipt' => NotificationDestination(
    id == null
        ? Routes.inbox
        : '${Routes.inbox}?item=${Uri.encodeQueryComponent(id)}&kind=${target == 'inbox_receipt' ? 'receipt' : 'sms'}',
  ),
  'export' => const NotificationDestination(Routes.exports),
  'audit_export' => NotificationDestination(
    id == null ? Routes.adminAudit : '${Routes.adminAudit}?export=${Uri.encodeQueryComponent(id)}',
  ),
  'subscription' => const NotificationDestination(Routes.subscription),
  'insight' => NotificationDestination(id == null ? Routes.insights : Routes.notificationDetailFor(id)),
  'activity' => NotificationDestination(Routes.activity, tab: true, activityFilter: activityQueryFrom(data)),
  'add_transaction' => const NotificationDestination(Routes.addTransaction),
  'home' => const NotificationDestination(Routes.home, tab: true),
  _ => null,
};

/// Push types that open the Subscription screen (older payloads).
const subscriptionPushTypes = {'subscription', 'payment_failed', 'subscription_prompt', 'subscription_expiration'};

NotificationDestination _byType(Map<String, dynamic> data) {
  final type = _str(data['type']);
  final itemType = _str(data['item_type']);
  final insightId = _str(data['insight_id']);
  switch (type) {
    case 'daily_summary':
      final summaryId = _str(data['summary_id'] ?? data['daily_summary_id']);
      return NotificationDestination(summaryId == null ? Routes.dailySummaries : Routes.dailySummaryById(summaryId));
    case 'export':
      return const NotificationDestination(Routes.exports);
    case 'audit_export_ready':
      final exportId = _str(data['export_id']);
      return NotificationDestination(
        exportId == null ? Routes.adminAudit : '${Routes.adminAudit}?export=${Uri.encodeQueryComponent(exportId)}',
      );
    case 'ai_unavailable':
      return const NotificationDestination(Routes.addTransaction);
    case 'inbox':
      return NotificationDestination(itemType == 'transaction' ? Routes.review : Routes.inbox);
    case 'budget_alert':
      final budgetId = _str(data['budget_id']);
      return NotificationDestination(budgetId == null ? Routes.budgets : Routes.budgetById(budgetId));
    case 'spending_spike':
      final q = activityQueryFrom(data);
      return NotificationDestination(
        Routes.activity,
        tab: true,
        activityFilter: TxnQuery(categoryId: q.categoryId, from: q.from, to: q.to, type: q.type ?? 'expense'),
      );
    case 'bill_due':
      final billId = _str(data['recurring_pattern_id'] ?? data['bill_id']);
      return billId == null
          ? const NotificationDestination(Routes.plan, tab: true)
          : NotificationDestination(Routes.billById(billId));
    case 'loan_repayment_due':
      final loanId = _str(data['loan_id']);
      return NotificationDestination(loanId == null ? Routes.loans : Routes.loanById(loanId));
    case 'investment_contribution_due' || 'investment_meeting' || 'investment_payout':
      final investmentId = _str(data['investment_id']);
      return NotificationDestination(investmentId == null ? Routes.investments : Routes.investmentById(investmentId));
    case 'savings_opportunity':
      final goalId = _str(data['goal_id']);
      return NotificationDestination(goalId == null ? Routes.goals : Routes.goalById(goalId));
    case 'summary':
      return const NotificationDestination(Routes.dailySummaries);
    case 'announcement':
      return NotificationDestination(insightId == null ? Routes.insights : Routes.notificationDetailFor(insightId));
  }
  if (subscriptionPushTypes.contains(type)) return const NotificationDestination(Routes.subscription);
  return NotificationDestination(insightId == null ? Routes.insights : Routes.notificationDetailFor(insightId));
}

/// Opens the screen a notification points at — from a push tap (foreground
/// banner, background or cold start) or a notification-centre action — and
/// marks the notification read. When nobody is signed in yet (or onboarding /
/// income setup is still open) the destination waits until the app shell
/// appears.
class NotificationRouter {
  NotificationRouter._();
  static final instance = NotificationRouter._();

  /// Data waiting for sign-in to finish.
  Map<String, dynamic>? pending;

  /// Whether the app is ready to show a destination. Replaceable in tests.
  bool Function(WidgetRef ref) isReady = _signedInAndSetUp;

  static bool _signedInAndSetUp(WidgetRef ref) {
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    return auth.status == AuthStatus.authenticated && user != null && user.declaredIncomeBracket != null;
  }

  /// Open [data]'s destination now, or remember it until [flushPending].
  /// Pass [router] when opening from inside the signed-in app (a
  /// notification-centre pill): it is then used directly.
  void open(WidgetRef ref, Map<String, dynamic> data, {GoRouter? router}) {
    _markRead(ref, _str(data['insight_id']));
    if (router == null && !isReady(ref)) {
      pending = Map<String, dynamic>.of(data);
      return;
    }
    go(ref, destinationFor(data), router: router);
  }

  /// Called when the signed-in app shell appears: open what was waiting.
  void flushPending(WidgetRef ref) {
    final data = pending;
    if (data == null || !isReady(ref)) return;
    pending = null;
    go(ref, destinationFor(data));
  }

  /// Forget anything waiting (sign-out).
  void clear() => pending = null;

  void go(WidgetRef ref, NotificationDestination d, {GoRouter? router}) {
    if (d.activityFilter != null) ref.read(activityFilterProvider.notifier).set(d.activityFilter!);
    final GoRouter r = router ?? ref.read(routerProvider);
    if (d.tab) {
      r.go(d.location);
    } else {
      unawaited(r.push(d.location));
    }
  }

  void _markRead(WidgetRef ref, String? insightId) {
    if (insightId == null) return;
    unawaited(
      ref
          .read(insightsRepositoryProvider)
          .markRead(insightId)
          .then((_) {
            ref
              ..invalidate(unreadInsightsCountProvider)
              ..invalidate(insightsProvider);
          })
          .catchError((_) {}),
    );
  }
}
