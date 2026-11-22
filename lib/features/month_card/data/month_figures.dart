import '../../activity/data/activity_models.dart';
import '../../dashboard/data/last_30_days.dart';
import '../../plan/data/plan_models.dart';

/// The first day of [d]'s calendar month.
DateTime monthStart(DateTime d) => DateTime(d.year, d.month, 1);

/// The last day of [month]'s calendar month.
DateTime monthEnd(DateTime month) => DateTime(month.year, month.month + 1, 0);

/// The calendar month before [d]'s (first day).
DateTime previousMonth(DateTime d) => DateTime(d.year, d.month - 1, 1);

/// `2026-10` for October 2026 (a stable key for a month).
String monthId(DateTime month) => '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

/// One of the biggest spending categories of the month.
class MonthCategory {
  const MonthCategory({required this.name, required this.minor, required this.share, required this.barFraction});

  final String name;

  /// Spent in this category, in minor units of [MonthFigures.currency].
  final int minor;

  /// Of all the month's spending (0..1).
  final double share;

  /// Bar length next to the biggest category (which is 1).
  final double barFraction;
}

/// What the shareable month card shows, computed from the month's
/// transactions with the same totals as Home ([summarisePeriod]): income that
/// does not count (money sent back, moves between your own money) and
/// spending that is not spending are left out.
class MonthFigures {
  const MonthFigures({
    required this.month,
    required this.currency,
    required this.incomeMinor,
    required this.spentMinor,
    required this.top,
    this.keptShare,
    this.changePercent,
    this.budgetsKept,
    this.budgetsTotal = 0,
  });

  /// First day of the month.
  final DateTime month;
  final String currency;
  final int incomeMinor;
  final int spentMinor;

  /// Share of what came in that was not spent (0..1); null with no income.
  final double? keptShare;

  /// Up to three categories, biggest first.
  final List<MonthCategory> top;

  /// Spending against the month before, in whole percent (negative: less);
  /// null when the month before has no spending to compare with.
  final int? changePercent;

  /// Monthly budgets whose spending stayed within the limit; null with none.
  final int? budgetsKept;
  final int budgetsTotal;

  /// Something to show: money came in or went out.
  bool get hasData => incomeMinor > 0 || spentMinor > 0;

  static const topCount = 3;
}

/// Figures for [month] from its transactions [txns], the previous month's
/// [priorTxns] (empty when unknown) and the user's [budgets].
MonthFigures computeMonthFigures({
  required DateTime month,
  required List<Txn> txns,
  List<Txn> priorTxns = const [],
  List<BudgetItem> budgets = const [],
  required String uncategorised,
}) {
  final summary = summarisePeriod(txns, uncategorised: uncategorised);
  final inMinor = summary.moneyIn.minorUnits;
  final outMinor = summary.moneyOut.minorUnits;

  final rows = summary.topCategories.take(MonthFigures.topCount).toList();
  final biggest = rows.isEmpty ? 0 : rows.first.amount.minorUnits;
  final top = [
    for (final r in rows)
      MonthCategory(
        name: r.name,
        minor: r.amount.minorUnits,
        share: outMinor > 0 ? r.amount.minorUnits / outMinor : 0,
        barFraction: biggest > 0 ? r.amount.minorUnits / biggest : 0,
      ),
  ];

  final priorOut = summarisePeriod(priorTxns, uncategorised: uncategorised).moneyOut.minorUnits;
  final change = priorOut > 0 ? ((outMinor - priorOut) * 100 / priorOut).round() : null;

  final (kept, total) = _budgetsKept(budgets, txns);

  return MonthFigures(
    month: monthStart(month),
    currency: summary.moneyOut.currency,
    incomeMinor: inMinor,
    spentMinor: outMinor,
    keptShare: inMinor > 0 ? ((inMinor - outMinor) / inMinor).clamp(0.0, 1.0) : null,
    top: top,
    changePercent: change,
    budgetsKept: total > 0 ? kept : null,
    budgetsTotal: total,
  );
}

/// Monthly budgets (active, saved) whose category's spending in [txns] stayed
/// within the limit. A budget with no category counts all spending.
(int kept, int total) _budgetsKept(List<BudgetItem> budgets, List<Txn> txns) {
  var kept = 0;
  var total = 0;
  for (final b in budgets) {
    if (!b.isActive || b.pending || b.period != 'monthly' || b.limit.minorUnits <= 0) continue;
    total++;
    var spent = 0;
    for (final t in txns) {
      if (t.type != 'expense' || !t.categoryIsSpending) continue;
      if (t.amount.currency != b.limit.currency) continue;
      if (b.categoryId != null && t.categoryId != b.categoryId) continue;
      spent += t.amount.minorUnits.abs();
    }
    if (spent <= b.limit.minorUnits) kept++;
  }
  return (kept, total);
}
