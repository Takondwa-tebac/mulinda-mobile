import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money.dart';
import 'package:mulinda_mobile/core/widgets/progress_bar.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:mulinda_mobile/features/dashboard/data/spending_insight.dart';
import 'package:mulinda_mobile/features/plan/data/budget_pace.dart';

Money _m(int minor, [String currency = 'MWK']) =>
    Money(minorUnits: minor, currency: currency, amount: minor / 100, formatted: '$currency ${minor ~/ 100}');

CategorySpend _row(String? id, String name, int now, int prev) =>
    CategorySpend(categoryId: id, name: name, amount: _m(now), previousAmount: _m(prev));

void main() {
  group('budget pace', () {
    // A 30-day period, 1–30 Nov.
    const from = '2026-11-01';
    const to = '2026-11-30';

    test('half the money at half the time is on track, projected to the limit', () {
      final p = budgetPace(spentMinor: 50000, limitMinor: 100000, from: from, to: to, now: DateTime(2026, 11, 15));
      expect(p.elapsedShare, closeTo(0.5, 1e-9));
      expect(p.projectedMinor, 100000);
      expect(p.health, BudgetHealth.onTrack);
      expect(p.overPace, isFalse);
    });

    test('spending faster than time is at risk with a projection above the limit', () {
      final p = budgetPace(spentMinor: 60000, limitMinor: 100000, from: from, to: to, now: DateTime(2026, 11, 12));
      expect(p.overPace, isTrue);
      expect(p.projectedMinor, 150000);
      expect(p.health, BudgetHealth.atRisk);
    });

    test('spending past the limit is over', () {
      final p = budgetPace(spentMinor: 120000, limitMinor: 100000, from: from, to: to, now: DateTime(2026, 11, 20));
      expect(p.health, BudgetHealth.over);
    });

    test('does not project in the first days of a period', () {
      final p = budgetPace(
        spentMinor: 20000,
        limitMinor: 100000,
        from: from,
        to: to,
        now: DateTime(2026, 11, 2),
        alertThreshold: 0.8,
      );
      expect(p.projectedMinor, isNull);
      expect(p.health, BudgetHealth.onTrack);
    });

    test('reaching the alert threshold is at risk even without a period', () {
      final p = budgetPace(spentMinor: 85000, limitMinor: 100000, alertThreshold: 0.8);
      expect(p.elapsedShare, isNull);
      expect(p.projectedMinor, isNull);
      expect(p.health, BudgetHealth.atRisk);
    });

    test('the last full period is the previous month or Monday–Sunday week', () {
      expect(lastFullPeriod('monthly', now: DateTime(2026, 11, 5)), ('2026-10-01', '2026-10-31'));
      expect(lastFullPeriod('monthly', now: DateTime(2026, 1, 10)), ('2025-12-01', '2025-12-31'));
      // 5 Nov 2026 is a Thursday.
      expect(lastFullPeriod('weekly', now: DateTime(2026, 11, 5)), ('2026-10-26', '2026-11-01'));
    });
  });

  group('spending insight', () {
    test('says nothing when the previous amount is zero', () {
      expect(spendingInsight([_row('c1', 'Transport', 5000, 0)]), isNull);
    });

    test('says nothing for empty or missing data', () {
      expect(spendingInsight(const []), isNull);
    });

    test('says nothing for small changes or the "Other" bucket', () {
      expect(spendingInsight([_row('c1', 'Food', 10500, 10000)]), isNull); // +5%
      expect(spendingInsight([_row(null, 'Other', 50000, 10000)]), isNull);
    });

    test('reports the category with the biggest change, from the numbers given', () {
      final i = spendingInsight([
        _row('c1', 'Food', 12000, 10000), // +20%, +2,000
        _row('c2', 'Transport', 11800, 10000), // +18%, +1,800
        _row('c3', 'Airtime', 2000, 4000), // -50%, -2,000 → tie on size, first wins
        _row('c4', 'Rent', 70000, 50000), // +40%, +20,000
      ])!;
      expect(i.categoryName, 'Rent');
      expect(i.percent, 40);
      expect(i.up, isTrue);
    });

    test('reports a fall too', () {
      final i = spendingInsight([_row('c1', 'Transport', 4100, 5000)])!;
      expect(i.up, isFalse);
      expect(i.percent, 18);
    });

    test('ignores rows whose amounts are in different currencies', () {
      final r = CategorySpend(categoryId: 'c1', name: 'Fuel', amount: _m(9000), previousAmount: _m(1000, 'USD'));
      expect(spendingInsight([r]), isNull);
    });
  });

  group('uncategorised share', () {
    test('is the part of spending with no category', () {
      expect(uncategorisedShare([_row(null, 'Other', 7500, 0), _row('c1', 'Food', 2500, 0)]), closeTo(0.75, 1e-9));
      expect(uncategorisedShare(const []), 0);
    });
  });

  group('dashboard additions', () {
    test('reads needs_attention and spending_by_category, and tolerates their absence', () {
      final d = DashboardSummary.fromJson({
        'categorisation': {'needs_attention': 12},
        'spending_by_category': [
          {
            'category_id': 'c1',
            'name': 'Transport',
            'icon': 'directions_bus',
            'color': '#3498DB',
            'amount': {'minor_units': 500000, 'currency': 'MWK', 'amount': 5000, 'formatted': 'MK 5,000.00'},
            'previous_amount': {'minor_units': 400000, 'currency': 'MWK', 'amount': 4000, 'formatted': 'MK 4,000.00'},
          },
        ],
      });
      expect(d.needsAttention, 12);
      expect(d.spendingByCategory.single.name, 'Transport');
      expect(d.spendingByCategory.single.previousAmount.minorUnits, 400000);

      final old = DashboardSummary.fromJson(const {});
      expect(old.needsAttention, isNull);
      expect(old.spendingByCategory, isEmpty);
      expect(old.isFirstRun, isTrue);
    });
  });
}
