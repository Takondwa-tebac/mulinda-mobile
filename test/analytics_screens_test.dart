import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mulinda_mobile/core/router/routes.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/core/widgets/report_table.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/analytics/data/analytics_models.dart';
import 'package:mulinda_mobile/features/analytics/screens/category_detail_screen.dart';
import 'package:mulinda_mobile/features/analytics/screens/money_received_screen.dart';
import 'package:mulinda_mobile/features/analytics/screens/money_spent_screen.dart';
import 'package:mulinda_mobile/features/analytics/screens/where_money_goes_screen.dart';
import 'package:mulinda_mobile/features/analytics/widgets/home_analytics.dart';
import 'package:mulinda_mobile/features/analytics/widgets/in_context_card.dart';

import 'support/analytics_fakes.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [overrides] replaces the default fixture overrides (pass a full
/// [analyticsOverrides] set).
Future<void> _pump(WidgetTester tester, Widget child, {List<Override> overrides = const [], bool dark = false}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.isEmpty ? analyticsOverrides() : overrides,
      child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: child),
    ),
  );
  await _settle(tester);
}

/// Scrolls the page (the first scrollable) until [finder] is fully on screen.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await _settle(tester);
}

/// The labels of every category row, in order (chart rows or table rows).
List<String> _rowKeys(WidgetTester tester, String prefix) => tester
    .widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix)))
    .map((w) => (w.key! as ValueKey<String>).value.substring(prefix.length))
    .toList();

/// The no-break space AmountText puts between the currency and the number.
final _nb = String.fromCharCode(0x00A0);

void main() {
  group('Where your money is going', () {
    for (final dark in [false, true]) {
      testWidgets('renders headline, rows, others and insights (${dark ? 'dark' : 'light'})', (tester) async {
        await _pump(tester, const WhereMoneyGoesScreen(), dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.text('MK${_nb}285,400'), findsWidgets);
        expect(find.byKey(const ValueKey('comparison-line')), findsOneWidget);
        expect(find.byKey(const ValueKey('breakdown-donut')), findsOneWidget);
        await _scrollTo(tester, find.byKey(const ValueKey('insight-categoryUp')));
        expect(find.byKey(const ValueKey('insight-biggestCategory')), findsOneWidget);
        expect(find.byKey(const ValueKey('insight-someFutureKey')), findsNothing);
      });
    }

    testWidgets('chart and table show the same rows and amounts', (tester) async {
      await _pump(tester, const WhereMoneyGoesScreen());
      final chartRows = _rowKeys(tester, 'category-row-');
      expect(chartRows, ['c-food', 'c-rent', 'c-transport', 'uncategorised', 'others']);
      expect(find.text('MK${_nb}98,600'), findsOneWidget);

      await tester.tap(find.text('analytics.tableView'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('breakdown-table')), findsOneWidget);
      expect(_rowKeys(tester, 'table-row-'), chartRows);
      final table = tester.widget<ReportTable>(find.byType(ReportTable));
      expect(table.rows.map((r) => r.cells[1]), ['MK 98,600', 'MK 60,000', 'MK 41,300', 'MK 27,500', 'MK 58,000']);
      // The total row equals the headline, and the shares add to 100.
      expect(table.footer![1], 'MK 285,400');
      final shares = table.rows.fold<int>(0, (s, r) => s + int.parse(r.cells[2].replaceAll('%', '')));
      expect(shares, 100);
    });

    testWidgets('Everything else expands to its members with the uncategorised tag', (tester) async {
      await _pump(tester, const WhereMoneyGoesScreen());
      await _scrollTo(tester, find.byKey(const ValueKey('category-row-others')));
      await tester.tap(find.byKey(const ValueKey('category-row-others')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('others-member-c-airtime')), findsOneWidget);
      expect(find.byKey(const ValueKey('others-member-c-bank')), findsOneWidget);
    });

    testWidgets('switching period asks for that period', (tester) async {
      final asked = <PeriodSelection>[];
      await _pump(
        tester,
        const WhereMoneyGoesScreen(),
        overrides: analyticsOverrides(
          categories: (k) {
            asked.add(k.period);
            return fixtureBreakdown(k.kind);
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('seg-this_month')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('period-previous')));
      await _settle(tester);
      expect(asked, contains(const PeriodSelection(PeriodKey.thisMonth)));
      expect(asked.last, const PeriodSelection(PeriodKey.thisMonth, offset: -1));
    });
  });

  group('Category detail', () {
    testWidgets('full: stats, trend, merchants and payments filtered to the category', (tester) async {
      final queries = <TxnQuery>[];
      await _pump(tester, const CategoryDetailScreen(categoryId: 'c-food'), overrides: analyticsOverrides(queries: queries));
      expect(tester.takeException(), isNull);
      expect(find.text('Food'), findsWidgets);
      expect(find.text('MK 2,800'), findsOneWidget);
      expect(find.byKey(const ValueKey('stat-highest')), findsOneWidget);
      await _scrollTo(tester, find.byKey(const ValueKey('trend-chart')));
      expect(find.byKey(const ValueKey('trend-story')), findsOneWidget);
      await _scrollTo(tester, find.byKey(const ValueKey('merchant-Shoprite')));
      await _scrollTo(tester, find.byKey(const ValueKey('see-all-payments')));
      expect(queries.last.categoryId, 'c-food');
      expect(queries.last.period, 'last_30_days');
      expect(queries.last.counted, isTrue);
    });

    testWidgets('trend chart and table list the same months', (tester) async {
      await _pump(tester, const CategoryDetailScreen(categoryId: 'c-food'));
      await _scrollTo(tester, find.text('analytics.tableView').last);
      await tester.tap(find.text('analytics.tableView').last);
      await _settle(tester);
      final table = tester.widget<ReportTable>(find.byKey(const ValueKey('trend-table')));
      expect(table.rows.map((r) => r.cells[1]), ['MK 88,900', 'MK 95,100', 'MK 90,400', 'MK 96,800', 'MK 71,200']);
    });

    testWidgets('thin: one uncategorised payment shows notes instead of stats and trend', (tester) async {
      final queries = <TxnQuery>[];
      await _pump(
        tester,
        const CategoryDetailScreen(categoryId: 'uncategorised'),
        overrides: analyticsOverrides(detail: (_) => fixtureDetail('category_detail_thin'), queries: queries),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('analytics.uncategorised'), findsWidgets);
      expect(find.byKey(const ValueKey('stats-need-two')), findsOneWidget);
      expect(find.byKey(const ValueKey('trend-needs-history')), findsOneWidget);
      expect(find.byKey(const ValueKey('stat-highest')), findsNothing);
      await _scrollTo(tester, find.byKey(const ValueKey('see-all-payments')));
      expect(queries.last.uncategorised, isTrue);
      expect(queries.last.categoryId, isNull);
    });
  });

  group('Money spent', () {
    testWidgets('day chart and table share the series; total equals headline', (tester) async {
      await _pump(tester, const MoneySpentScreen());
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('day-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('where-it-went')), findsOneWidget);
      await _scrollTo(tester, find.text('analytics.tableView'));
      await tester.tap(find.text('analytics.tableView'));
      await _settle(tester);
      final table = tester.widget<ReportTable>(find.byKey(const ValueKey('day-table')));
      expect(table.rows, hasLength(3));
      expect(table.rows.map((r) => r.cells[1]), ['MK 3,900', 'MK 15,250', 'MK 12,500']);
      expect(table.rows.last.cells.first, endsWith('analytics.soFarSuffix'));
      expect(table.footer![1], 'MK 285,400');
    });

    testWidgets('an empty day shows the empty state and no chart', (tester) async {
      await _pump(
        tester,
        const MoneySpentScreen(initial: PeriodSelection(PeriodKey.today)),
        overrides: analyticsOverrides(summary: (_) => fixtureSummary('summary_today_empty')),
      );
      expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);
      expect(find.text('analytics.empty.todayTitle'), findsOneWidget);
      expect(find.byKey(const ValueKey('day-chart')), findsNothing);
      expect(find.byKey(const ValueKey('comparison-line')), findsNothing);
    });
  });

  testWidgets('Money received: coverage note, not counted, senders', (tester) async {
    await _pump(tester, const MoneyReceivedScreen(), dark: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('coverage-note')), findsOneWidget);
    expect(find.text('MK${_nb}407,000'), findsWidgets);
    await _scrollTo(tester, find.byKey(const ValueKey('not-counted')));
    await _scrollTo(tester, find.byKey(const ValueKey('need-more-history')));
    await _scrollTo(tester, find.byKey(const ValueKey('party-FDH Bank')));
  });

  testWidgets('In context card from the transaction context', (tester) async {
    final txn = Txn.fromJson(analyticsFixture('transaction_context'));
    await _pump(
      tester,
      Scaffold(body: ListView(children: [InContextCard(txn: txn, period: PeriodSelection.defaultPeriod)])),
    );
    expect(find.byKey(const ValueKey('in-context-card')), findsOneWidget);
    expect(find.text('analytics.ctx.biggestInCategory'), findsOneWidget);
    expect(find.text('analytics.ctx.shareOfCategory'), findsOneWidget);
    expect(find.text('analytics.ctx.merchantCount'), findsOneWidget);
    expect(find.byKey(const ValueKey('see-all-from-merchant')), findsOneWidget);
  });

  group('Home analytics block', () {
    Future<GoRouter> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ListView(children: const [HomeAnalyticsHero(), SizedBox(height: 16), HomeWhereCard()]),
            ),
          ),
          GoRoute(path: Routes.analyticsSpent, builder: (_, s) => MoneySpentScreen(initial: PeriodSelection.fromParams(s.uri.queryParameters))),
          GoRoute(path: Routes.analyticsReceived, builder: (_, s) => MoneyReceivedScreen(initial: PeriodSelection.fromParams(s.uri.queryParameters))),
          GoRoute(path: Routes.analyticsSpending, builder: (_, s) => WhereMoneyGoesScreen(initial: PeriodSelection.fromParams(s.uri.queryParameters))),
          GoRoute(
            path: Routes.analyticsCategoryPath,
            builder: (_, s) => CategoryDetailScreen(categoryId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/transactions/:id', builder: (_, s) => Text('txn ${s.pathParameters['id']} ${s.uri.queryParameters['context_period']}')),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: analyticsOverrides(),
          child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
        ),
      );
      await _settle(tester);
      return router;
    }

    testWidgets('shows the sentence, figures, comparison and top categories', (tester) async {
      await pumpHome(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('analytics.home.leftOver'), findsOneWidget);
      expect(find.text('MK${_nb}407,000'), findsOneWidget);
      expect(find.text('84'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-where-row-c-food')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-where-more')), findsOneWidget);
    });

    testWidgets('Money spent figure opens the Money spent report', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('home-fig-spent')));
      await _settle(tester);
      expect(find.byType(MoneySpentScreen), findsOneWidget);
    });

    testWidgets('Money received figure opens the Money received report', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('home-fig-received')));
      await _settle(tester);
      expect(find.byType(MoneyReceivedScreen), findsOneWidget);
    });

    testWidgets('Biggest expense opens the transaction with report context', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('home-fig-biggest')));
      await _settle(tester);
      expect(find.text('txn t-rent last_30_days'), findsOneWidget);
    });

    testWidgets('a category row opens Category detail and See all opens the report', (tester) async {
      final router = await pumpHome(tester);
      await _scrollTo(tester, find.byKey(const ValueKey('home-where-row-c-food')));
      await tester.tap(find.byKey(const ValueKey('home-where-row-c-food')));
      await _settle(tester);
      expect(find.byType(CategoryDetailScreen), findsOneWidget);
      router.pop();
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('home-where-more')));
      await _settle(tester);
      expect(find.byType(WhereMoneyGoesScreen), findsOneWidget);
    });
  });
}
