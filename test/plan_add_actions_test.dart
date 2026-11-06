import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mulinda_mobile/core/router/routes.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/plan/data/plan_repository.dart';
import 'package:mulinda_mobile/features/plan/screens/plan_lists.dart';
import 'package:mulinda_mobile/features/shell/app_shell.dart';

Map<String, dynamic> _m(int major) => {
  'minor_units': major * 100,
  'currency': 'MWK',
  'amount': major,
  'formatted': 'MK $major.00',
};

final _budget = BudgetItem.fromJson({
  'id': 'b1',
  'name': 'Transport',
  'period': 'monthly',
  'limit': _m(35000),
  'status': {'spent': _m(1000), 'percentage': 3},
});

/// The budgets list inside a router that records where "add" goes.
Future<List<String>> _pumpBudgets(WidgetTester tester, List<BudgetItem> items) async {
  final visited = <String>[];
  final router = GoRouter(
    initialLocation: Routes.budgets,
    routes: [
      GoRoute(path: Routes.budgets, builder: (_, _) => const BudgetsListScreen()),
      GoRoute(
        path: Routes.budgetForm,
        builder: (_, s) {
          visited.add(Routes.budgetForm);
          return const Scaffold(body: Text('form'));
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [budgetsProvider.overrideWith((ref) async => items)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return visited;
}

void main() {
  test('the capture button shows on Home and Activity only', () {
    expect(showsCaptureButton(0), isTrue);
    expect(showsCaptureButton(1), isTrue);
    expect(showsCaptureButton(2), isFalse);
    expect(showsCaptureButton(3), isFalse);
  });

  testWidgets('a plan list has no floating button, an app-bar + and an add row', (tester) async {
    final visited = await _pumpBudgets(tester, [_budget]);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byKey(const ValueKey('plan-list-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-list-add-row')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-list-add-row')));
    await tester.pumpAndSettle();
    expect(visited, [Routes.budgetForm]);
  });

  testWidgets('the app-bar + opens the form', (tester) async {
    final visited = await _pumpBudgets(tester, [_budget]);
    await tester.tap(find.byKey(const ValueKey('plan-list-add')));
    await tester.pumpAndSettle();
    expect(visited, [Routes.budgetForm]);
  });

  testWidgets('an empty list offers to create the first one', (tester) async {
    final visited = await _pumpBudgets(tester, []);
    expect(find.text('plan2.empty.budgets'), findsOneWidget);
    await tester.tap(find.text('plan2.addBudget'));
    await tester.pumpAndSettle();
    expect(visited, [Routes.budgetForm]);
  });
}
