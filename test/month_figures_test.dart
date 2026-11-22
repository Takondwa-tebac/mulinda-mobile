import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/month_card/data/month_figures.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';

Map<String, dynamic> _m(int major) => {
  'minor_units': major * 100,
  'currency': 'MWK',
  'amount': major,
  'formatted': 'MK $major.00',
};

var _seq = 0;

Txn _t(String type, int major, {String? cat, String? name, bool spending = true}) => Txn.fromJson({
  'id': 't${_seq++}',
  'type': type,
  'amount': _m(major),
  'occurred_at': '2026-10-10T09:00:00Z',
  if (cat != null) 'category': {'id': cat, 'name': name ?? cat, 'is_spending': spending},
});

BudgetItem _budget(String id, int limit, {String? cat, String period = 'monthly', bool active = true}) =>
    BudgetItem.fromJson({
      'id': id,
      'name': id,
      'category_id': cat,
      'period': period,
      'limit': _m(limit),
      'is_active': active,
    });

final _october = DateTime(2026, 10, 1);

void main() {
  group('month figures', () {
    test('kept from what came in: income minus spending over income', () {
      final f = computeMonthFigures(
        month: _october,
        txns: [_t('income', 100000, cat: 'salary'), _t('expense', 65000, cat: 'food')],
        uncategorised: 'none',
      );
      expect(f.incomeMinor, 10000000);
      expect(f.spentMinor, 6500000);
      expect(f.keptShare, closeTo(0.35, 1e-9));
      expect(f.hasData, isTrue);
    });

    test('kept is clamped to 0 when spending is more than income, and null with no income', () {
      final over = computeMonthFigures(
        month: _october,
        txns: [_t('income', 1000), _t('expense', 5000)],
        uncategorised: 'none',
      );
      expect(over.keptShare, 0);

      final noIncome = computeMonthFigures(month: _october, txns: [_t('expense', 5000)], uncategorised: 'none');
      expect(noIncome.keptShare, isNull);
      expect(noIncome.hasData, isTrue);
    });

    test('non-counting income and non-spending expenses are left out, like Home', () {
      final f = computeMonthFigures(
        month: _october,
        txns: [
          _t('income', 50000, cat: 'salary'),
          // "Sent and returned" and moves between own money are not income.
          _t('income', 20000, cat: 'returned', name: 'Sent and returned', spending: false),
          _t('income', 30000, cat: 'own', name: 'Moving my money', spending: false),
          _t('expense', 10000, cat: 'food'),
          _t('expense', 40000, cat: 'own', name: 'Moving my money', spending: false),
          _t('transfer', 25000),
        ],
        uncategorised: 'none',
      );
      expect(f.incomeMinor, 5000000);
      expect(f.spentMinor, 1000000);
      expect(f.keptShare, closeTo(0.8, 1e-9));
      expect(f.top.map((c) => c.name), ['food']);
    });

    test('top 3 categories, biggest first, with shares of spending and bar lengths', () {
      final f = computeMonthFigures(
        month: _october,
        txns: [
          _t('expense', 62000, cat: 'people', name: 'Sent to people'),
          _t('expense', 30000, cat: 'food', name: 'Food'),
          _t('expense', 18200, cat: 'food', name: 'Food'),
          _t('expense', 31500, cat: 'transport', name: 'Transport'),
          _t('expense', 9600, cat: 'airtime', name: 'Airtime'),
        ],
        uncategorised: 'none',
      );
      expect(f.top.map((c) => c.name), ['Sent to people', 'Food', 'Transport']);
      expect(f.top.length, MonthFigures.topCount);
      expect(f.top[0].barFraction, 1);
      expect(f.top[1].minor, 4820000);
      expect(f.top[1].barFraction, closeTo(48200 / 62000, 1e-9));
      expect(f.top[0].share, closeTo(62000 / 151300, 1e-9));
    });

    test('uncategorised spending is named with the given label', () {
      final f = computeMonthFigures(month: _october, txns: [_t('expense', 500)], uncategorised: 'No category yet');
      expect(f.top.single.name, 'No category yet');
    });

    test('change against the month before: less, more, and missing', () {
      List<Txn> spend(int major) => [_t('expense', major, cat: 'food')];

      final less = computeMonthFigures(month: _october, txns: spend(88000), priorTxns: spend(100000), uncategorised: '');
      expect(less.changePercent, -12);

      final more = computeMonthFigures(month: _october, txns: spend(125000), priorTxns: spend(100000), uncategorised: '');
      expect(more.changePercent, 25);

      final none = computeMonthFigures(month: _october, txns: spend(1000), uncategorised: '');
      expect(none.changePercent, isNull);

      // A month before with only non-spending moves has nothing to compare with.
      final onlyMoves = computeMonthFigures(
        month: _october,
        txns: spend(1000),
        priorTxns: [_t('expense', 9000, cat: 'own', spending: false)],
        uncategorised: '',
      );
      expect(onlyMoves.changePercent, isNull);
    });

    test('budgets kept: monthly, active budgets whose spending stayed within the limit', () {
      final f = computeMonthFigures(
        month: _october,
        txns: [
          _t('expense', 40000, cat: 'food'),
          _t('expense', 30000, cat: 'transport'),
          _t('expense', 5000, cat: 'own', spending: false),
        ],
        budgets: [
          _budget('food', 50000, cat: 'food'), // kept
          _budget('transport', 25000, cat: 'transport'), // over
          _budget('everything', 80000), // no category: all spending, 70,000, kept
          _budget('weekly', 1, cat: 'food', period: 'weekly'), // not monthly: left out
          _budget('paused', 1, cat: 'food', active: false), // inactive: left out
        ],
        uncategorised: '',
      );
      expect(f.budgetsTotal, 3);
      expect(f.budgetsKept, 2);
    });

    test('no budgets: no budgets figure', () {
      final f = computeMonthFigures(month: _october, txns: [_t('expense', 100)], uncategorised: '');
      expect(f.budgetsKept, isNull);
      expect(f.budgetsTotal, 0);
    });

    test('nothing recorded: no data', () {
      final f = computeMonthFigures(month: _october, txns: [_t('transfer', 1000)], uncategorised: '');
      expect(f.hasData, isFalse);
      expect(f.top, isEmpty);
    });
  });

  group('month helpers', () {
    test('month bounds and the month before, across a year', () {
      expect(monthStart(DateTime(2026, 11, 22, 15)), DateTime(2026, 11, 1));
      expect(monthEnd(DateTime(2026, 2, 1)), DateTime(2026, 2, 28));
      expect(monthEnd(DateTime(2026, 12, 1)), DateTime(2026, 12, 31));
      expect(previousMonth(DateTime(2027, 1, 3)), DateTime(2026, 12, 1));
      expect(monthId(DateTime(2026, 3, 1)), '2026-03');
    });
  });
}
