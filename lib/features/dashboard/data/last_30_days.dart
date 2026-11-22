import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_json.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import 'dashboard_models.dart';

/// Money in, money out and the top spending categories over a window (the
/// last 30 days after the first-run import).
class PeriodSummary {
  const PeriodSummary({required this.moneyIn, required this.moneyOut, required this.topCategories});

  final Money moneyIn;
  final Money moneyOut;

  /// Biggest spending categories first, at most [maxCategories].
  final List<CategorySpend> topCategories;

  bool get isEmpty => moneyIn.minorUnits == 0 && moneyOut.minorUnits == 0;

  static const maxCategories = 4;
}

/// Totals for [txns]: income in, spending out (transfers and moves between the
/// user's own money are left out), grouped by category. [uncategorised] names
/// spending with no category yet.
PeriodSummary summarisePeriod(List<Txn> txns, {required String uncategorised}) {
  final currency = txns.isEmpty ? 'MWK' : txns.first.amount.currency;
  var inMinor = 0;
  var outMinor = 0;
  final byCategory = <String, ({String name, String? icon, String? color, String? id, int minor})>{};

  for (final t in txns) {
    final minor = t.amount.minorUnits.abs();
    if (t.countsAsIncome) {
      inMinor += minor;
    } else if (t.type == 'expense' && t.categoryIsSpending) {
      outMinor += minor;
      final key = t.categoryId ?? '';
      final prev = byCategory[key];
      byCategory[key] = (
        name: t.categoryName ?? uncategorised,
        icon: t.categoryIcon,
        color: t.categoryColor,
        id: t.categoryId,
        minor: (prev?.minor ?? 0) + minor,
      );
    }
  }

  Money money(int minor) => Money.fromJson(moneyJson(minor / 100, currency));
  final rows = byCategory.values.toList()..sort((a, b) => b.minor.compareTo(a.minor));
  return PeriodSummary(
    moneyIn: money(inMinor),
    moneyOut: money(outMinor),
    topCategories: [
      for (final r in rows.take(PeriodSummary.maxCategories))
        CategorySpend(
          categoryId: r.id,
          name: r.name,
          icon: r.icon,
          color: r.color,
          amount: money(r.minor),
          previousAmount: money(0),
        ),
    ],
  );
}

/// The last 30 days, from the transaction list (a few pages at most).
final last30DaysProvider = FutureProvider.autoDispose<PeriodSummary>((ref) async {
  final repo = ref.read(activityRepositoryProvider);
  final now = DateTime.now();
  final query = TxnQuery(from: now.subtract(const Duration(days: 30)), to: now);
  final txns = <Txn>[];
  for (var page = 1; page <= 5; page++) {
    final result = await repo.transactionsPage(query, page: page, perPage: 100);
    txns.addAll(result.items);
    if (!result.hasMore) break;
  }
  return summarisePeriod(txns, uncategorised: 'home3.noCategory'.tr());
});
