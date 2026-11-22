import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money.dart';
import 'package:mulinda_mobile/features/plan/data/month_budget_total.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';

Money _m(int minor, [String currency = 'MWK']) =>
    Money(minorUnits: minor, currency: currency, amount: minor / 100, formatted: '$currency ${minor ~/ 100}');

BudgetItem _b(String? category, int limit, int spent, {String period = 'monthly', String currency = 'MWK', bool active = true}) =>
    BudgetItem(
      id: '${category ?? 'all'}-$period-$limit',
      name: category ?? 'Everything',
      categoryId: category,
      period: period,
      limit: _m(limit, currency),
      spent: _m(spent, currency),
      percentage: 0,
      isExceeded: false,
      alertThreshold: 0.8,
      isActive: active,
    );

void main() {
  test('category budgets are added together', () {
    final t = monthBudgetTotal([_b('food', 100000, 40000), _b('transport', 50000, 10000)])!;
    expect(t.limitMinor, 150000);
    expect(t.spentMinor, 50000);
    expect(t.currency, 'MWK');
  });

  test('an overall budget is not added on top of its category budgets', () {
    final t = monthBudgetTotal([_b(null, 300000, 120000), _b('food', 100000, 40000), _b('transport', 50000, 10000)])!;
    expect(t.limitMinor, 300000);
    expect(t.spentMinor, 120000);
  });

  test('weekly and paused budgets are left out of the monthly total', () {
    final t = monthBudgetTotal([
      _b('food', 100000, 40000),
      _b('transport', 20000, 5000, period: 'weekly'),
      _b('fun', 30000, 1000, active: false),
    ])!;
    expect(t.limitMinor, 100000);
    expect(t.spentMinor, 40000);
  });

  test('two budgets for the same category count once', () {
    final t = monthBudgetTotal([_b('food', 100000, 40000), _b('food', 80000, 40000)])!;
    expect(t.limitMinor, 100000);
    expect(t.spentMinor, 40000);
  });

  test('only the most common currency is totalled', () {
    final t = monthBudgetTotal([_b('food', 100000, 1), _b('rent', 200000, 2), _b('trip', 500, 3, currency: 'USD')])!;
    expect(t.currency, 'MWK');
    expect(t.limitMinor, 300000);
  });

  test('no monthly budgets means no card', () {
    expect(monthBudgetTotal([_b('food', 20000, 1, period: 'weekly')]), isNull);
    expect(monthBudgetTotal([]), isNull);
  });
}
