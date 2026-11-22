import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import '../../dashboard/data/last_30_days.dart';
import '../../plan/data/plan_models.dart';
import '../../plan/data/plan_repository.dart';
import 'month_figures.dart';

/// The month's figures (see [computeMonthFigures]) for [month], the first day
/// of a calendar month. The month before and the budgets are optional: when
/// they cannot be loaded, the comparison and budgets figures are left out.
final monthFiguresProvider = FutureProvider.autoDispose.family<MonthFigures, DateTime>((ref, month) async {
  final repo = ref.read(activityRepositoryProvider);
  final prior = previousMonth(month);
  final results = await Future.wait([
    transactionsBetween(repo, from: month, to: monthEnd(month), maxPages: 10),
    transactionsBetween(repo, from: prior, to: monthEnd(prior), maxPages: 10).catchError((_) => <Txn>[]),
  ]);
  final budgets = await ref.read(planRepositoryProvider).budgets().catchError((_) => <BudgetItem>[]);
  return computeMonthFigures(
    month: month,
    txns: results[0],
    priorTxns: results[1],
    budgets: budgets,
    uncategorised: 'home3.noCategory'.tr(),
  );
});
