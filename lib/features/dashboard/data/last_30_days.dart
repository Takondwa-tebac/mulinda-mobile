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
PeriodSummary summarisePeriod(List<Txn> txns, {required String uncategorised, String others = 'Everything else'}) {
  final currency = txns.isEmpty ? 'MWK' : txns.first.amount.currency;
  var inMinor = 0;
  var outMinor = 0;
  final byCategory = <String, ({String name, String? icon, String? color, String? id, int minor})>{};

  // Fees and levies arrive nested under their transaction; they are money
  // spent too, so they count alongside the transactions themselves.
  final all = [for (final t in txns) ...[t, ...t.children]];
  for (final t in all) {
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
  final fits = rows.length <= PeriodSummary.maxCategories;
  final shown = rows.take(fits ? rows.length : PeriodSummary.maxCategories - 1).toList();
  final restMinor = rows.skip(shown.length).fold<int>(0, (s, r) => s + r.minor);
  return PeriodSummary(
    moneyIn: money(inMinor),
    moneyOut: money(outMinor),
    topCategories: [
      for (final r in shown)
        CategorySpend(
          categoryId: r.id,
          name: r.name,
          icon: r.icon,
          color: r.color,
          amount: money(r.minor),
          previousAmount: money(0),
        ),
      // The rest are grouped so the chart still adds up to all spending.
      if (restMinor > 0) CategorySpend(name: others, amount: money(restMinor), previousAmount: money(0)),
    ],
  );
}

/// Every transaction between [from] and [to] (inclusive local dates), read a
/// page at a time, at most [maxPages] pages of 100.
Future<List<Txn>> transactionsBetween(
  ActivityRepository repo, {
  required DateTime from,
  required DateTime to,
  int maxPages = 5,
}) async {
  final query = TxnQuery(from: from, to: to);
  final txns = <Txn>[];
  for (var page = 1; page <= maxPages; page++) {
    final result = await repo.transactionsPage(query, page: page, perPage: 100);
    txns.addAll(result.items);
    if (!result.hasMore) break;
  }
  return txns;
}

/// The last 30 days, from the transaction list (a few pages at most).
final last30DaysProvider = FutureProvider.autoDispose<PeriodSummary>((ref) async {
  final now = DateTime.now();
  final txns = await transactionsBetween(
    ref.read(activityRepositoryProvider),
    from: now.subtract(const Duration(days: 30)),
    to: now,
  );
  return summarisePeriod(txns, uncategorised: 'home3.noCategory'.tr(), others: 'home3.otherCategories'.tr());
});
