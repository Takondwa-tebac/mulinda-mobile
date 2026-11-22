import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/analytics/analytics_nav.dart';
import 'package:mulinda_mobile/features/analytics/data/analytics_models.dart';

import 'support/analytics_fakes.dart';

void main() {
  group('Money.formatted_whole', () {
    test('is read when sent and falls back to formatted', () {
      final whole = Money.fromJson({'minor_units': 100, 'currency': 'MWK', 'amount': 1, 'formatted': 'MK 1.00', 'formatted_whole': 'MK 1'});
      expect(whole.whole, 'MK 1');
      final old = Money.fromJson({'minor_units': 100, 'currency': 'MWK', 'amount': 1, 'formatted': 'MK 1.00'});
      expect(old.formattedWhole, isNull);
      expect(old.whole, 'MK 1.00');
    });
  });

  group('summary', () {
    test('parses the last 30 days', () {
      final s = fixtureSummary();
      expect(s.period.key, PeriodKey.last30Days);
      expect(s.period.from, DateTime(2026, 10, 24));
      expect(s.period.inProgress, isTrue);
      expect(s.period.partlyCovered, isFalse);
      expect(s.expense.whole, 'MK 285,400');
      expect(s.expenseCount, 76);
      expect(s.totalCount, 84);
      expect(s.typicalDay?.whole, 'MK 5,400');
      expect(s.biggestExpense?.id, 't-rent');
      expect(s.biggestExpense?.category?.name, 'Rent');
      expect(s.expenseComparison.comparable, isTrue);
      expect(s.expenseComparison.direction, ComparisonDirection.down);
      expect(s.expenseComparison.showPct, isFalse);
      expect(s.expenseComparison.previousAmount?.whole, 'MK 312,900');
      expect(s.series, hasLength(3));
      expect(s.series!.last.complete, isFalse);
      expect(s.topCategoriesShare, 70);
      expect(s.notCounted.count, 1);
      // Sorted by priority.
      expect(s.insights.map((i) => i.key), ['biggestDay', 'typicalDay']);
      expect(s.insights.first.target?.type, 'day');
    });

    test('today with nothing spent: not comparable, nulls and empty', () {
      final s = fixtureSummary('summary_today_empty');
      expect(s.isEmpty, isTrue);
      expect(s.series, isNull);
      expect(s.typicalDay, isNull);
      expect(s.biggestExpense, isNull);
      expect(s.topCategoriesShare, isNull);
      expect(s.period.coverageFrom, isNull);
      final c = s.expenseComparison;
      expect(c.comparable, isFalse);
      expect(c.dayInProgress, isTrue);
      expect(c.previousAmount, isNull);
      expect(c.difference, isNull);
      expect(c.direction, isNull);
      expect(c.pct, isNull);
    });
  });

  group('categories', () {
    test('expense rows, uncategorised row, others group and insights', () {
      final b = fixtureBreakdown(ReportKind.expense);
      expect(b.kind, ReportKind.expense);
      expect(b.rows.map((r) => r.name), ['Food', 'Rent', 'Transport', null]);
      final uncategorised = b.rows.last;
      expect(uncategorised.isUncategorised, isTrue);
      expect(uncategorised.routeId, 'uncategorised');
      expect(uncategorised.needsCategory, isTrue);
      expect(b.rows[1].comparison.insufficientHistory, isTrue);
      expect(b.rows[2].comparison.comparable, isFalse); // null comparison
      expect(b.rows[1].previousAmount, isNull);
      expect(b.others?.members.map((m) => m.name), ['Airtime', 'Bank charges']);
      final shares = b.rows.fold<int>(0, (s, r) => s + r.sharePct) + b.others!.sharePct;
      expect(shares, 100);
      expect(b.parties, isEmpty);
      // At most three, by priority; unknown keys are parsed but never shown.
      expect(b.insights.map((i) => i.key), ['categoryUp', 'biggestCategory', 'topThreeShare']);
    });

    test('income with parties, not counted and no comparison', () {
      final b = fixtureBreakdown(ReportKind.income);
      expect(b.kind, ReportKind.income);
      expect(b.others, isNull);
      expect(b.parties.single.name, 'FDH Bank');
      expect(b.notCounted.amount.whole, 'MK 80,000');
      expect(b.comparison.insufficientHistory, isTrue);
      expect(b.period.partlyCovered, isTrue);
    });
  });

  group('category detail', () {
    test('full detail', () {
      final d = fixtureDetail();
      expect(d.category?.name, 'Food');
      expect(d.median?.whole, 'MK 2,800');
      expect(d.highest?.title, 'Shoprite City Centre');
      expect(d.lowest?.amount.whole, 'MK 500');
      expect(d.trend?.points, hasLength(5));
      expect(d.trend!.points.last.complete, isFalse);
      expect(d.steady, isTrue);
      expect(d.merchants.last.name, isNull);
    });

    test('thin detail: null median, highest, lowest, trend and steady', () {
      final d = fixtureDetail('category_detail_thin');
      expect(d.category, isNull);
      expect(d.count, 1);
      expect(d.median, isNull);
      expect(d.highest, isNull);
      expect(d.lowest, isNull);
      expect(d.trend, isNull);
      expect(d.steady, isNull);
      expect(d.total.whole, 'MK 1,500.00');
    });
  });

  test('transaction context', () {
    final ctx = TxnContext.parse(analyticsFixture('transaction_context')['context'])!;
    expect(ctx.shareOfCategoryPct, 19);
    expect(ctx.rankInCategory, 1);
    expect(ctx.categoryCount, 23);
    expect(ctx.merchant?.name, 'Shoprite');
    expect(ctx.isEmpty, isFalse);
    expect(TxnContext.parse(null), isNull);
    final nothing = TxnContext.parse({'period': {}, 'category_total': null, 'merchant': null})!;
    expect(nothing.isEmpty, isTrue);
  });

  group('period selection', () {
    test('query parameters, stepping and reading back', () {
      expect(PeriodSelection.defaultPeriod.toParams(), {'period': 'last_30_days'});
      final prev = const PeriodSelection(PeriodKey.thisMonth).previous;
      expect(prev.toParams(), {'period': 'this_month', 'offset': '-1'});
      expect(prev.next, const PeriodSelection(PeriodKey.thisMonth));
      expect(const PeriodSelection(PeriodKey.thisMonth).next, isNull);
      final custom = PeriodSelection.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 15));
      expect(custom.toParams(), {'period': 'custom', 'from': '2026-11-01', 'to': '2026-11-15'});
      expect(PeriodSelection.fromParams(custom.toParams()), custom);
      expect(PeriodSelection.fromParams({'context_period': 'today', 'context_offset': '-2'}, prefix: 'context_'),
          const PeriodSelection(PeriodKey.today, offset: -2));
      expect(PeriodSelection.fromParams({'period': 'nonsense'}), PeriodSelection.defaultPeriod);
      expect(PeriodSelection.fromParams({'period': 'custom'}), PeriodSelection.defaultPeriod);
    });

    test('report lists ask for counted rows of the same period', () {
      final q = AnalyticsNav.query(const PeriodSelection(PeriodKey.thisWeek, offset: -1), kind: ReportKind.expense, uncategorised: true);
      expect(q.toParams(), {'type': 'expense', 'period': 'this_week', 'offset': -1, 'uncategorised': 1, 'counted': 1});
      expect(q.isDefault, isFalse);
      // Clearing the period drops the report-only flags with it.
      final cleared = q.withoutPeriod();
      expect(cleared.period, isNull);
      expect(cleared.counted, isFalse);
      expect(const TxnQuery(merchant: 'Shoprite').toParams(), {'merchant': 'Shoprite'});
    });
  });
}
