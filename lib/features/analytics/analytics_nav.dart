import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../activity/data/activity_feed.dart';
import '../activity/data/activity_models.dart';
import 'data/analytics_models.dart';
import 'presentation/analytics_text.dart';

/// Where every figure, row and link on the reports leads.
abstract class AnalyticsNav {
  static String _with(String path, Map<String, String> query) =>
      Uri(path: path, queryParameters: query.isEmpty ? null : query).toString();

  static String spendingLocation(PeriodSelection p) => _with(Routes.analyticsSpending, p.toParams());
  static String spentLocation(PeriodSelection p) => _with(Routes.analyticsSpent, p.toParams());
  static String receivedLocation(PeriodSelection p) => _with(Routes.analyticsReceived, p.toParams());

  static String categoryLocation(String id, PeriodSelection p, {ReportKind kind = ReportKind.expense}) =>
      _with(Routes.analyticsCategory(id), {...p.toParams(), 'kind': kind.name});

  /// Transaction detail with the "In context" block for [p].
  static String transactionLocation(String id, PeriodSelection p) =>
      _with(Routes.transactionById(id), {for (final e in p.toParams().entries) 'context_${e.key}': e.value});

  static void spending(BuildContext context, PeriodSelection p) => context.push(spendingLocation(p));
  static void spent(BuildContext context, PeriodSelection p) => context.push(spentLocation(p));
  static void received(BuildContext context, PeriodSelection p) => context.push(receivedLocation(p));

  static void category(BuildContext context, String id, PeriodSelection p, {ReportKind kind = ReportKind.expense}) =>
      context.push(categoryLocation(id, p, kind: kind));

  static void transaction(BuildContext context, String id, PeriodSelection p) =>
      context.push(transactionLocation(id, p));

  /// The Activity filters that list exactly the transactions behind a report
  /// figure (same period, so the list sums to it).
  static TxnQuery query(
    PeriodSelection p, {
    AnalyticsPeriod? period,
    ReportKind? kind,
    String? categoryId,
    bool uncategorised = false,
    String? merchant,
  }) => TxnQuery(
    period: p.key.api,
    offset: p.offset,
    from: p.key == PeriodKey.custom ? p.from : null,
    to: p.key == PeriodKey.custom ? p.to : null,
    type: kind?.name,
    categoryId: categoryId,
    uncategorised: uncategorised,
    merchant: merchant,
    counted: true,
    periodLabel: periodChipLabel(p, period),
  );

  /// Activity filtered to [query] ("See all").
  static void activity(BuildContext context, WidgetRef ref, TxnQuery query) {
    ref.read(activityFilterProvider.notifier).set(query);
    context.go(Routes.activity);
  }

  /// The transactions of one day (a "biggest day" insight).
  static void day(BuildContext context, WidgetRef ref, DateTime day, {ReportKind? kind}) {
    final p = PeriodSelection.custom(day, day);
    activity(context, ref, query(p, kind: kind).copyWith(periodLabel: () => fmtWeekday(day)));
  }

  /// Follow an insight's target.
  static void insight(BuildContext context, WidgetRef ref, Insight i, PeriodSelection p, {ReportKind kind = ReportKind.expense}) {
    final target = i.target;
    if (i.key == 'biggestDay') {
      final d = parseDay(i.params['date']) ?? (target?.type == 'day' ? parseDay(target!.id) : null);
      if (d != null) day(context, ref, d, kind: kind);
      return;
    }
    if (target == null) return;
    switch (target.type) {
      case 'category':
        category(context, target.id, p, kind: kind);
      case 'transaction':
        transaction(context, target.id, p);
      case 'day':
        final d = parseDay(target.id);
        if (d != null) day(context, ref, d, kind: kind);
    }
  }
}
