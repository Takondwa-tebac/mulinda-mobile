import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mulinda_mobile/core/network/api_exception.dart';
import 'package:mulinda_mobile/core/router/id_routes.dart';
import 'package:mulinda_mobile/core/router/routes.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/plan/data/bill_models.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/plan/data/plan_repository.dart';
import 'package:mulinda_mobile/features/plan/screens/bill_detail_screen.dart';
import 'package:mulinda_mobile/features/plan/screens/goal_detail_screen.dart';
import 'package:mulinda_mobile/features/plan/screens/plan_detail_screens.dart';
import 'package:mulinda_mobile/features/plan/widgets/budget_spending.dart';
import 'package:mulinda_mobile/features/summary/data/summary_models.dart';
import 'package:mulinda_mobile/features/summary/data/summary_repository.dart';
import 'package:mulinda_mobile/features/transactions/screens/transaction_detail_screen.dart';

Map<String, dynamic> _m(int major) => {
  'minor_units': major * 100,
  'currency': 'MWK',
  'amount': major,
  'formatted': 'MK $major.00',
};

final _gone = ApiException('Not found', statusCode: 404);

/// Answers each by-id call, or 404 for ids starting with "gone".
class _FakePlan extends PlanRepository {
  _FakePlan() : super(Dio());

  final calls = <String>[];

  Future<T> _answer<T>(String what, String id, T Function() make) async {
    calls.add('$what/$id');
    if (id.startsWith('gone')) throw _gone;
    return make();
  }

  @override
  Future<BudgetItem> budget(String id) => _answer(
    'budget',
    id,
    () => BudgetItem.fromJson({
      'id': id,
      'name': 'Transport',
      'period': 'monthly',
      'limit': _m(35000),
      'status': {'spent': _m(1000), 'percentage': 3},
    }),
  );

  @override
  Future<GoalItem> goal(String id) => _answer(
    'goal',
    id,
    () => GoalItem.fromJson({'id': id, 'name': 'School fees', 'target': _m(1000), 'current': _m(10)}),
  );

  @override
  Future<LoanItem> loan(String id) => _answer(
    'loan',
    id,
    () => LoanItem.fromJson({'id': id, 'name': 'Demo loan', 'principal': _m(50000), 'status': 'active'}),
  );

  @override
  Future<Bill> bill(String id) => _answer(
    'bill',
    id,
    () => Bill.fromJson({
      'id': id,
      'label': 'ESCOM electricity',
      'cadence': 'monthly',
      'average_amount': _m(18000),
      'next_due_on': '2026-11-25',
      'category': {'id': 'c1', 'name': 'Utilities', 'icon': 'bolt', 'color': '#F1C40F'},
      'recent_transactions': [
        {'id': 't1', 'type': 'expense', 'merchant': 'ESCOM', 'amount': _m(17500), 'occurred_at': '2026-10-25T09:00:00'},
      ],
    }),
  );
}

class _FakeSummaries extends SummaryRepository {
  _FakeSummaries() : super(Dio());

  @override
  Future<DailySummaryWithTransactions> getSummaryWithTransactions(String id) async {
    if (id.startsWith('gone')) throw _gone;
    return DailySummaryWithTransactions.fromJson({
      'id': id,
      'date': '2026-11-05',
      'income': _m(0),
      'expense': _m(3000),
      'net': _m(-3000),
      'transaction_count': 0,
      'transactions': [],
    });
  }
}

class _FakeActivity extends ActivityRepository {
  _FakeActivity() : super(Dio());

  @override
  Future<Txn> transaction(String id) async => throw _gone;
}

Future<_FakePlan> _open(WidgetTester tester, String location, {Object? extra}) async {
  final plan = _FakePlan();
  final router = GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      for (final list in [
        Routes.budgets,
        Routes.goals,
        Routes.loans,
        Routes.plan,
        Routes.activity,
        Routes.dailySummaries,
      ])
        GoRoute(
          path: list,
          builder: (_, _) => Scaffold(body: Text('list:$list')),
        ),
      ...idDetailRoutes(),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWithValue(plan),
        summaryRepositoryProvider.overrideWithValue(_FakeSummaries()),
        activityRepositoryProvider.overrideWithValue(_FakeActivity()),
        budgetSpendProvider.overrideWith((ref, key) async => const <Txn>[]),
        goalContributionsProvider.overrideWith((ref, id) async => const <GoalContribution>[]),
        loanRepaymentsProvider.overrideWith((ref, id) async => const <LoanRepayment>[]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push(location, extra: extra);
  await tester.pumpAndSettle();
  return plan;
}

void main() {
  testWidgets('a budget opened by id loads itself', (tester) async {
    final plan = await _open(tester, Routes.budgetById('b1'));
    expect(plan.calls, ['budget/b1']);
    expect(find.byType(BudgetDetailScreen), findsOneWidget);
  });

  testWidgets('a budget passed as extra is not fetched again', (tester) async {
    final b = BudgetItem.fromJson({
      'id': 'b2',
      'name': 'Food',
      'limit': _m(1),
      'status': {'spent': _m(0)},
    });
    final plan = await _open(tester, Routes.budgetById('b2'), extra: b);
    expect(plan.calls, isEmpty);
    expect(find.byType(BudgetDetailScreen), findsOneWidget);
  });

  testWidgets('goal and loan open by id', (tester) async {
    final plan = await _open(tester, Routes.goalById('g1'));
    expect(find.byType(GoalDetailScreen), findsOneWidget);
    expect(plan.calls, ['goal/g1']);
  });

  testWidgets('a loan opens by id', (tester) async {
    await _open(tester, Routes.loanById('l1'));
    expect(find.byType(LoanDetailScreen), findsOneWidget);
  });

  testWidgets('a bill opens by id with its recent payments', (tester) async {
    await _open(tester, Routes.billById('p1'));
    expect(find.byType(BillDetailScreen), findsOneWidget);
    expect(find.text('ESCOM electricity'), findsOneWidget);
    expect(find.text('MK 18000.00'), findsOneWidget);
    expect(find.text('ESCOM'), findsOneWidget);
  });

  testWidgets('a deleted budget goes back to the list with a message', (tester) async {
    await _open(tester, Routes.budgetById('gone-1'));
    expect(find.text('list:${Routes.budgets}'), findsOneWidget);
    expect(find.text('common.itemGone'), findsOneWidget);
  });

  testWidgets('a deleted bill goes to Plan', (tester) async {
    await _open(tester, Routes.billById('gone-2'));
    expect(find.text('list:${Routes.plan}'), findsOneWidget);
  });

  testWidgets('a deleted transaction goes to Activity', (tester) async {
    await _open(tester, Routes.transactionById('gone-3'));
    expect(find.byType(TransactionDetailScreen), findsNothing);
    expect(find.text('list:${Routes.activity}'), findsOneWidget);
  });

  testWidgets('a daily summary opens by id, and a deleted one goes to the list', (tester) async {
    await _open(tester, Routes.dailySummaryById('s1'));
    expect(find.textContaining('2026'), findsWidgets);

    await _open(tester, Routes.dailySummaryById('gone-4'));
    expect(find.text('list:${Routes.dailySummaries}'), findsOneWidget);
  });
}
