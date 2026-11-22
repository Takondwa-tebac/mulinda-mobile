import 'plan_models.dart';

/// What the "This month" card adds up: one currency, nothing counted twice.
class MonthBudgetTotal {
  const MonthBudgetTotal({required this.currency, required this.limitMinor, required this.spentMinor});

  final String currency;
  final int limitMinor;
  final int spentMinor;
}

/// Totals for the "This month" card, or null when no active monthly budget
/// exists.
///
/// Only active monthly budgets count (weekly ones measure a different window).
/// An overall budget (no category) already covers every category, so when one
/// exists the category budgets are not added on top of it. Otherwise each
/// category is counted once. Totals only make sense in one currency, so the
/// most common currency is used.
MonthBudgetTotal? monthBudgetTotal(List<BudgetItem> budgets) {
  final monthly = budgets.where((b) => b.isActive && b.period == 'monthly').toList();
  if (monthly.isEmpty) return null;

  final byCurrency = <String, List<BudgetItem>>{};
  for (final b in monthly) {
    byCurrency.putIfAbsent(b.limit.currency, () => []).add(b);
  }
  final main = byCurrency.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);

  final overall = main.value.where((b) => b.categoryId == null).toList();
  final List<BudgetItem> counted;
  if (overall.isNotEmpty) {
    // Several overall budgets overlap completely; the largest is the plan.
    counted = [overall.reduce((a, b) => a.limit.minorUnits >= b.limit.minorUnits ? a : b)];
  } else {
    final byCategory = <String, BudgetItem>{};
    for (final b in main.value) {
      final prev = byCategory[b.categoryId!];
      if (prev == null || b.limit.minorUnits > prev.limit.minorUnits) byCategory[b.categoryId!] = b;
    }
    counted = byCategory.values.toList();
  }

  return MonthBudgetTotal(
    currency: main.key,
    limitMinor: counted.fold<int>(0, (s, b) => s + b.limit.minorUnits),
    spentMinor: counted.fold<int>(0, (s, b) => s + b.spent.minorUnits),
  );
}
