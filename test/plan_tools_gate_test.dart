import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/stories/data/stories_repository.dart';
import 'package:mulinda_mobile/features/stories/data/story_visibility.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:mulinda_mobile/features/dashboard/screens/home_screen.dart';
import 'package:mulinda_mobile/features/insights/data/insights_repository.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/plan/data/plan_repository.dart';
import 'package:mulinda_mobile/features/plan/data/plan_tools_gate.dart';
import 'package:mulinda_mobile/features/plan/screens/plan_screen.dart';
import 'package:mulinda_mobile/shared/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/analytics_fakes.dart';

Map<String, dynamic> _m(int major) => {
  'minor_units': major * 100,
  'currency': 'MWK',
  'amount': major,
  'formatted': 'MK $major.00',
};

final _now = DateTime(2026, 11, 22, 10);

DashboardSummary _dashboard({int loans = 0, int investments = 0, int projects = 0}) => DashboardSummary.fromJson({
  'net_worth': _m(50000),
  'this_month': {'income': _m(150000), 'expense': _m(84600), 'net': _m(65400), 'savings_rate': 0.4},
  'budgets': {'total': 0},
  'goals': {'active': 1},
  'loans': {'active': loans, 'total_outstanding': _m(loans * 1000)},
  'investments': {'count': investments, 'total_value': _m(investments * 1000)},
  'projects': {'active': projects},
  'recent_transactions': const [],
});

User _user({DateTime? createdAt}) => User.fromJson({
  'id': 'u1',
  'first_name': 'Chisomo',
  'last_name': 'Phiri',
  'username': 'chisomo',
  'email': 'c@example.com',
  if (createdAt != null) 'created_at': createdAt.toUtc().toIso8601String(),
});

void main() {
  group('the rules', () {
    PlanToolsGate gate({
      DateTime? createdAt,
      bool? commitments = false,
      bool unlocked = false,
      bool done = false,
    }) => planToolsGate(
      createdAt: createdAt,
      now: _now,
      hasCommitments: commitments,
      unlocked: unlocked,
      moreOnPlanDone: done,
    );

    test('a new user (day 3) has commitments hidden until day 14', () {
      final g = gate(createdAt: DateTime(2026, 11, 20, 8));
      expect(g.hideCommitments, isTrue);
      expect(g.showMoreOnPlan, isFalse);
      expect(g.unlockDay, DateTime(2026, 12, 4));
      expect(isEarlyAccount(DateTime(2026, 11, 20), _now), isTrue);
    });

    test('anyone with a loan, investment or project sees everything from day 1', () {
      expect(gate(createdAt: DateTime(2026, 11, 20), commitments: true).hideCommitments, isFalse);
      expect(hasCommitments(_dashboard(loans: 1)), isTrue);
      expect(hasCommitments(_dashboard(investments: 1)), isTrue);
      expect(hasCommitments(_dashboard(projects: 1)), isTrue);
      expect(hasCommitments(_dashboard()), isFalse);
    });

    test('"Show them now" unlocks early, and no day-14 card follows', () {
      expect(gate(createdAt: DateTime(2026, 11, 20), unlocked: true).hideCommitments, isFalse);
      final later = gate(createdAt: DateTime(2026, 11, 1), unlocked: true);
      expect(later.showMoreOnPlan, isFalse);
    });

    test('from day 14 everything shows and Home offers "More on your Plan" once', () {
      // Created 8 November: day 14 is 22 November (today).
      final g = gate(createdAt: DateTime(2026, 11, 8, 23));
      expect(g.hideCommitments, isFalse);
      expect(g.showMoreOnPlan, isTrue);
      expect(gate(createdAt: DateTime(2026, 11, 8), done: true).showMoreOnPlan, isFalse);
      // Not for someone who already has a loan, nor while that is unknown.
      expect(gate(createdAt: DateTime(2026, 11, 8), commitments: true).showMoreOnPlan, isFalse);
      expect(gate(createdAt: DateTime(2026, 11, 8), commitments: null).showMoreOnPlan, isFalse);
    });

    test('day 13 is still early', () {
      expect(gate(createdAt: DateTime(2026, 11, 9)).hideCommitments, isTrue);
    });

    test('accounts long past day 14 are not told about "two weeks"', () {
      expect(gate(createdAt: DateTime(2026, 6, 1)).showMoreOnPlan, isFalse);
    });

    test('no sign-up date (older server or cached user): everything shows', () {
      final g = gate();
      expect(g.hideCommitments, isFalse);
      expect(g.showMoreOnPlan, isFalse);
      expect(isEarlyAccount(null, _now), isFalse);
    });

    test('created_at is read from the API user', () {
      expect(_user(createdAt: DateTime.utc(2026, 11, 20, 6)).createdAt, DateTime.utc(2026, 11, 20, 6));
      expect(_user().createdAt, isNull);
    });
  });

  group('the screens', () {
    Future<void> pump(
      WidgetTester tester,
      Widget screen, {
      required User user,
      required DashboardSummary dashboard,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      tester.view.physicalSize = const Size(360 * 3, 3000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => _now),
            currentUserProvider.overrideWith((ref) => user),
            dashboardProvider.overrideWith((ref) async => dashboard),
            budgetsProvider.overrideWith((ref) async => const <BudgetItem>[]),
            goalsProvider.overrideWith((ref) async => const <GoalItem>[]),
            advisoryProvider.overrideWith((ref) async => const AdvisorySummary()),
            reviewTransactionsProvider.overrideWith((ref) async => const []),
            unreadInsightsCountProvider.overrideWith((ref) async => 0),
            homeMonthStoryProvider.overrideWith((ref) async => null),
            yearStoryStatusProvider.overrideWith((ref) async => null),
            accountsProvider.overrideWith((ref) async => const <Account>[]),
            ...analyticsOverrides(),
          ],
          child: MaterialApp(theme: AppTheme.light, home: screen),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final newUser = _user(createdAt: DateTime(2026, 11, 20, 8));
    final day14User = _user(createdAt: DateTime(2026, 11, 8, 8));

    testWidgets('Home hides loans and investments for a new user, keeps budgets and goals', (tester) async {
      await pump(tester, const HomeScreen(), user: newUser, dashboard: _dashboard());
      expect(tester.takeException(), isNull);
      expect(find.text('home.budgets'), findsOneWidget);
      expect(find.text('home.goals'), findsOneWidget);
      expect(find.text('home.loans'), findsNothing);
      expect(find.text('home.investments'), findsNothing);
    });

    testWidgets('Home shows loans for a new user who already has one', (tester) async {
      await pump(tester, const HomeScreen(), user: newUser, dashboard: _dashboard(loans: 1));
      expect(find.text('home.loans'), findsOneWidget);
      expect(find.text('home.investments'), findsOneWidget);
    });

    testWidgets('Home shows everything when the sign-up date is unknown', (tester) async {
      await pump(tester, const HomeScreen(), user: _user(), dashboard: _dashboard());
      expect(find.text('home.loans'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-more-on-plan')), findsNothing);
    });

    testWidgets('Plan shows "More tools from" instead of commitments, and "Show them now" unlocks for good', (
      tester,
    ) async {
      await pump(tester, const PlanScreen(), user: newUser, dashboard: _dashboard());
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('plan-more-tools')), findsOneWidget);
      expect(find.text('plan2.commitments'), findsNothing);
      expect(find.text('plan.loans'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('plan-show-tools-now')));
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-more-tools')), findsNothing);
      expect(find.text('plan2.commitments'), findsOneWidget);
      expect(find.text('plan.projects'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(planToolsUnlockedKey('u1')), isTrue);
    });

    testWidgets('Plan remembers an early unlock', (tester) async {
      await pump(
        tester,
        const PlanScreen(),
        user: newUser,
        dashboard: _dashboard(),
        prefs: {planToolsUnlockedKey('u1'): true},
      );
      expect(find.byKey(const ValueKey('plan-more-tools')), findsNothing);
      expect(find.text('plan2.commitments'), findsOneWidget);
    });

    testWidgets('Plan add menu leaves out loans, investments and projects while early', (tester) async {
      await pump(tester, const PlanScreen(), user: newUser, dashboard: _dashboard());
      await tester.tap(find.byKey(const ValueKey('plan-add-menu')));
      // Not pumpAndSettle: Plan has a repeating animation.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      Finder item(String label) => find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text(label));
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
      expect(item('plan2.newBudget'), findsOneWidget);
      expect(item('plan2.newGoal'), findsOneWidget);
      expect(item('plan2.newLoan'), findsNothing);
      expect(item('plan2.newInvestment'), findsNothing);
      expect(item('plan2.newProject'), findsNothing);
    });

    testWidgets('on day 14 Home shows "More on your Plan" once; "Not now" puts it away for good', (tester) async {
      await pump(tester, const HomeScreen(), user: day14User, dashboard: _dashboard());
      expect(find.byKey(const ValueKey('home-more-on-plan')), findsOneWidget);
      expect(find.text('home.loans'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-more-on-plan-later')));
      await tester.pump();
      expect(find.byKey(const ValueKey('home-more-on-plan')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(moreOnPlanDoneKey('u1')), isTrue);
    });

    testWidgets('after it was dismissed, the day-14 card stays away', (tester) async {
      await pump(
        tester,
        const HomeScreen(),
        user: day14User,
        dashboard: _dashboard(),
        prefs: {moreOnPlanDoneKey('u1'): true},
      );
      expect(find.byKey(const ValueKey('home-more-on-plan')), findsNothing);
    });
  });
}
