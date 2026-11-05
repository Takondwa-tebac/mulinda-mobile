// Renders the redesigned screens at a 360 px wide phone with realistic data and
// fails on any layout overflow or exception.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/activity/screens/activity_screen.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/capture/data/inbox_repository.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:mulinda_mobile/features/dashboard/screens/home_screen.dart';
import 'package:mulinda_mobile/features/insights/data/insights_repository.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/plan/data/plan_repository.dart';
import 'package:mulinda_mobile/features/plan/screens/plan_screen.dart';
import 'package:mulinda_mobile/features/profile/screens/profile_screen.dart';

Map<String, dynamic> _m(int major) => {
  'minor_units': major * 100,
  'currency': 'MWK',
  'amount': major,
  'formatted': 'MK ${major.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}.00',
};

final _now = DateTime.now();
String _iso(int daysAgo, int hour) =>
    DateTime(_now.year, _now.month, _now.day, hour).subtract(Duration(days: daysAgo)).toIso8601String();

final _txns = [
  for (var i = 0; i < 12; i++)
    Txn.fromJson({
      'id': 't$i',
      'type': i % 4 == 0 ? 'income' : 'expense',
      'merchant': i.isEven ? 'Shoprite Lilongwe City Centre Branch' : 'Airtel Money',
      'amount': _m(1500 * (i + 1)),
      'occurred_at': _iso(i ~/ 3, 9 + i),
      'category': i == 3
          ? null
          : {'id': 'c$i', 'name': 'Groceries & household', 'icon': 'shopping_cart', 'color': '#E67E22'},
      'categorisation': {'status': i % 3 == 0 ? 'suggested' : 'confirmed', 'needs_attention': i % 3 == 0},
      'needs_review': i == 1,
    }),
];

final _dashboard = DashboardSummary.fromJson({
  'net_worth': _m(1250000),
  'this_month': {'income': _m(450000), 'expense': _m(312500), 'net': _m(137500), 'savings_rate': 0.3},
  'indicators': {
    'health_score': {'score': 72, 'grade': 'B'},
    'creditworthiness': {'score': 640, 'band': 'Fair'},
    'savings_rule': {'name': '50/30/20', 'on_track': true},
  },
  'budgets': {'total': 3, 'exceeded': 1},
  'goals': {'active': 2},
  'loans': {'active': 1, 'total_outstanding': _m(900000)},
  'investments': {'count': 2, 'total_value': _m(2000000)},
  'projects': {'active': 1},
  'recent_transactions': [
    {
      'id': 'r1',
      'date': _iso(0, 9).split('T').first,
      'type': 'expense',
      'amount': _m(12000),
      'merchant': 'Chipiku Stores',
      'category': 'Groceries',
    },
    {'id': 'r2', 'date': _iso(1, 9).split('T').first, 'type': 'income', 'amount': _m(350000), 'merchant': 'Salary'},
  ],
  'categorisation': {'needs_attention': 4},
  'spending_by_category': [
    {'category_id': 'c1', 'name': 'Transport', 'color': '#3498DB', 'amount': _m(118000), 'previous_amount': _m(100000)},
    {'category_id': 'c2', 'name': 'Groceries', 'color': '#E67E22', 'amount': _m(90000), 'previous_amount': _m(95000)},
    {'category_id': null, 'name': 'Other', 'amount': _m(20000), 'previous_amount': _m(0)},
  ],
});

final _budgets = [
  BudgetItem.fromJson({
    'id': 'b1',
    'name': 'Food and groceries for the family',
    'category_id': 'c2',
    'period': 'monthly',
    'limit': _m(100000),
    'alert_threshold': 0.8,
    'status': {
      'from': DateTime(_now.year, _now.month, 1).toIso8601String().split('T').first,
      'to': DateTime(_now.year, _now.month + 1, 0).toIso8601String().split('T').first,
      'spent': _m(90000),
      'percentage': 90,
    },
  }),
  BudgetItem.fromJson({
    'id': 'b2',
    'name': 'Fuel',
    'period': 'weekly',
    'limit': _m(20000),
    'status': {'spent': _m(25000), 'percentage': 125, 'is_exceeded': true},
  }),
];

final _goals = [
  GoalItem.fromJson({'id': 'g1', 'name': 'Emergency fund', 'target': _m(500000), 'current': _m(300000)}),
  GoalItem.fromJson({'id': 'g2', 'name': 'School fees', 'target': _m(200000), 'current': _m(200000)}),
];

final _user = User.fromJson({
  'id': 'u1',
  'first_name': 'Chikondi',
  'last_name': 'Banda',
  'username': 'chikondi',
  'email': 'chikondi@example.com',
});

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardProvider.overrideWith((ref) async => _dashboard),
        budgetsProvider.overrideWith((ref) async => _budgets),
        goalsProvider.overrideWith((ref) async => _goals),
        advisoryProvider.overrideWith((ref) async => const AdvisorySummary()),
        transactionsProvider.overrideWith((ref) async => _txns),
        accountsProvider.overrideWith((ref) async => const []),
        reviewTransactionsProvider.overrideWith((ref) async => [_txns[1]]),
        categoriesProvider.overrideWith((ref) async => const []),
        unreadInsightsCountProvider.overrideWith((ref) async => 2),
        pendingCountProvider.overrideWith((ref) => 0),
        currentUserProvider.overrideWith((ref) => _user),
      ],
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  // Let the futures resolve; avoid pumpAndSettle (the skeleton shimmer repeats).
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Home renders at 360 px', (tester) async {
    await _pump(tester, const HomeScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('home2.needsAttention'), findsOneWidget);
    expect(find.text('home2.whereMoneyWent'), findsOneWidget);
    // Transport: 118,000 vs 100,000 → +18%, computed from the numbers given.
    expect(find.text('home2.insightUp'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity renders grouped by day at 360 px', (tester) async {
    await _pump(tester, const ActivityScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('common.today'), findsOneWidget);
    expect(find.text('activity2.filterNeedsCategory (4)'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plan renders at 360 px', (tester) async {
    await _pump(tester, const PlanScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('plan2.thisPeriod'), findsOneWidget);
    expect(find.text('plan2.status.over'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pump();
    expect(find.text('plan2.milestoneDone'), findsOneWidget);
    expect(find.text('plan2.milestoneHalf'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile renders and asks before logging out', (tester) async {
    await _pump(tester, const ProfileScreen());
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('profile.logOut'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('profile.logOut'));
    await tester.pumpAndSettle();
    expect(find.text('profile2.logoutTitle'), findsOneWidget);
    await tester.tap(find.text('common.cancel'));
    await tester.pumpAndSettle();
    expect(find.text('profile2.logoutTitle'), findsNothing);
  });
}
