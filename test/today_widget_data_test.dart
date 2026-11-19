import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:mulinda_mobile/features/home_widget/today_widget_data.dart';
import 'package:mulinda_mobile/features/home_widget/today_widget_sync.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/summary/data/summary_models.dart';

Money mk(int kwacha) =>
    Money(minorUnits: kwacha * 100, currency: 'MWK', amount: kwacha.toDouble(), formatted: 'MK $kwacha');

const _en = {
  'title': 'Today',
  'noAllowance': 'Add a budget to get a daily limit',
  'left': '{amount} left',
  'over': '{amount} over',
  'overBy': 'Over by {amount}',
  'onTrack': 'On track',
  'challengeLabel': "Today's challenge",
  'challengeStayUnder': 'Stay under {amount}',
  'challengeLog': 'Log everything you spend today',
  'loggedCount': '{count} logged',
  'noTransactions': 'No transactions yet',
  'transaction': 'Transaction',
};

String t(String key, {Map<String, String>? args}) {
  var s = _en[key] ?? key;
  args?.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

DailySummary day(String date, {int expense = 0, int count = 1}) => DailySummary(
      id: date,
      date: date,
      income: mk(0),
      expense: mk(expense),
      net: mk(-expense),
      transactionCount: count,
    );

BudgetItem budget({required int limit, required int spent, String from = '2026-11-01', String to = '2026-11-30'}) =>
    BudgetItem(
      id: 'b',
      name: 'Food',
      categoryId: null,
      period: 'monthly',
      limit: mk(limit),
      spent: mk(spent),
      percentage: spent / limit * 100,
      isExceeded: spent > limit,
      alertThreshold: 0.8,
      isActive: true,
      periodFrom: from,
      periodTo: to,
    );

DashboardSummary dashboard({int income = 0, int expense = 0, List<RecentTxn> recent = const []}) => DashboardSummary(
      netWorth: mk(0),
      thisMonth: MonthSummary(income: mk(income), expense: mk(expense), net: mk(income - expense), savingsRate: 0),
      indicators: const Indicators(
        healthScore: 78,
        healthGrade: 'B',
        creditScore: 0,
        creditBand: '',
        savingsRuleName: '',
        savingsOnTrack: true,
      ),
      budgetsTotal: 0,
      budgetsExceeded: 0,
      goalsActive: 0,
      loansActive: 0,
      loansOutstanding: mk(0),
      investmentsCount: 0,
      investmentsValue: mk(0),
      investmentsGain: mk(0),
      projectsActive: 0,
      recent: recent,
    );

void main() {
  // Thursday 19 November 2026, 12 days left in the month including today.
  final now = DateTime(2026, 11, 19, 14, 5);

  group('dailyAllowanceMinor', () {
    test('spreads what is left of the budgets before today over the days left', () {
      // 300,000 limit, 126,000 spent of which 6,000 today: 180,000 / 12 days.
      final allowance = dailyAllowanceMinor(
        now: now,
        currency: 'MWK',
        spentTodayMinor: 600000,
        budgets: [budget(limit: 200000, spent: 100000), budget(limit: 100000, spent: 26000)],
      );
      expect(allowance, 1500000);
    });

    test('falls back to this month\'s income when there are no budgets', () {
      final allowance = dailyAllowanceMinor(
        now: now,
        currency: 'MWK',
        spentTodayMinor: 0,
        budgets: const [],
        dashboard: dashboard(income: 240000, expense: 0),
      );
      expect(allowance, 2000000);
    });

    test('is null with no budgets and no income', () {
      expect(
        dailyAllowanceMinor(now: now, currency: 'MWK', spentTodayMinor: 0, budgets: const [], dashboard: dashboard()),
        isNull,
      );
    });

    test('ignores budgets whose period does not cover today', () {
      final allowance = dailyAllowanceMinor(
        now: now,
        currency: 'MWK',
        spentTodayMinor: 0,
        budgets: [budget(limit: 50000, spent: 0, from: '2026-10-01', to: '2026-10-31')],
      );
      expect(allowance, isNull);
    });
  });

  group('loggingStreak', () {
    test('counts back from today when something is logged today', () {
      final streak = loggingStreak(
        now: now,
        today: day('2026-11-19'),
        history: [day('2026-11-18'), day('2026-11-17'), day('2026-11-15')],
      );
      expect(streak, 3);
    });

    test('counts back from yesterday when nothing is logged yet today', () {
      final streak = loggingStreak(
        now: now,
        today: day('2026-11-19', count: 0),
        history: [day('2026-11-18'), day('2026-11-17')],
      );
      expect(streak, 2);
    });

    test('days with no transactions break the streak', () {
      final streak = loggingStreak(
        now: now,
        today: day('2026-11-19'),
        history: [day('2026-11-18', count: 0), day('2026-11-17')],
      );
      expect(streak, 1);
    });
  });

  group('buildTodayWidgetData', () {
    test('on track: teal bar, amount left, last transaction', () {
      final data = buildTodayWidgetData(
        now: now,
        t: t,
        today: day('2026-11-19', expense: 6000),
        budgets: [budget(limit: 300000, spent: 126000)],
        history: [day('2026-11-18'), day('2026-11-17')],
        dashboard: dashboard(recent: [
          RecentTxn(id: '1', date: '2026-11-19', type: 'expense', amount: mk(6000), merchant: 'Shoprite'),
        ]),
      );
      expect(data.title, 'Today');
      expect(data.spent, 'MK 6,000');
      expect(data.left, 'MK 9,000 left');
      expect(data.bars, [true, true, false, false, false]);
      expect(data.warn, isFalse);
      expect(data.challengeText, 'Stay under MK 15,000');
      expect(data.challengeStatus, 'On track');
      expect(data.streak, '🔥 3');
      expect(data.lastTxn, 'Shoprite');
      expect(data.lastAmount, '-6,000');
      expect(data.challengeLabel, "TODAY'S CHALLENGE");
    });

    test('past 80% the widget warns; past 100% it shows how much over', () {
      final close = buildTodayWidgetData(
        now: now,
        t: t,
        today: day('2026-11-19', expense: 13250),
        budgets: [budget(limit: 300000, spent: 133250)],
      );
      expect(close.warn, isTrue);
      expect(close.bars, [true, true, true, true, true]);
      expect(close.challengeStatus, 'MK 1,750 left');

      final over = buildTodayWidgetData(
        now: now,
        t: t,
        today: day('2026-11-19', expense: 16000),
        budgets: [budget(limit: 300000, spent: 136000)],
      );
      expect(over.left, 'MK 1,000 over');
      expect(over.challengeStatus, 'Over by MK 1,000');
    });

    test('without an allowance it asks for a budget and counts what was logged', () {
      final data = buildTodayWidgetData(now: now, t: t, today: day('2026-11-19', expense: 2000, count: 2));
      expect(data.left, 'Add a budget to get a daily limit');
      expect(data.bars, everyElement(isFalse));
      expect(data.challengeText, 'Log everything you spend today');
      expect(data.challengeStatus, '2 logged');
      expect(data.lastTxn, 'No transactions yet');
      expect(data.streak, '');
    });

    test('no em dashes in any widget copy', () {
      final data = buildTodayWidgetData(now: now, t: t, today: day('2026-11-19', expense: 2000));
      for (final s in [data.left, data.challengeText, data.challengeStatus, data.streak]) {
        expect(s.contains('—'), isFalse, reason: s);
      }
    });
  });

  test('only money writes trigger a widget refresh', () {
    expect(isWidgetRelevantWrite('POST', '/v1/transactions'), isTrue);
    expect(isWidgetRelevantWrite('post', '/v1/sms/ingest'), isTrue);
    expect(isWidgetRelevantWrite('POST', '/v1/receipt-scans'), isTrue);
    expect(isWidgetRelevantWrite('GET', '/v1/transactions'), isFalse);
    expect(isWidgetRelevantWrite('POST', '/v1/auth/login'), isFalse);
    expect(isWidgetRelevantWrite('POST', '/v1/coach/ask'), isFalse);
  });
}
