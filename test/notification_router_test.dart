import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mulinda_mobile/core/notifications/in_app_banner.dart';
import 'package:mulinda_mobile/core/notifications/notification_router.dart';
import 'package:mulinda_mobile/core/router/app_router.dart';
import 'package:mulinda_mobile/core/router/routes.dart';
import 'package:mulinda_mobile/features/activity/data/activity_feed.dart';
import 'package:mulinda_mobile/features/insights/data/insights_repository.dart';
import 'package:mulinda_mobile/features/insights/widgets/notification_card.dart';

String _to(Map<String, dynamic> data) => destinationFor(data).location;

class _FakeInsights extends InsightsRepository {
  _FakeInsights() : super(Dio());

  final read = <String>[];

  @override
  Future<void> markRead(String id) async => read.add(id);
}

/// A tiny app whose router records every screen it shows.
class _Harness {
  late WidgetRef ref;
  late GoRouter router;
  late ProviderContainer container;
  final insights = _FakeInsights();

  /// The screen on top (pushed screens are not in the router's base uri).
  String get location {
    final shown = find.textContaining('screen:').evaluate().map((e) => (e.widget as Text).data!).last;
    final where = shown.substring('screen:'.length);
    return where == 'home' ? Routes.home : where;
  }

  Future<void> pump(WidgetTester tester) async {
    Widget screen(String name) => Scaffold(body: Text('screen:$name'));
    router = GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (_, _) => Consumer(
            builder: (_, r, _) {
              ref = r;
              return screen('home');
            },
          ),
        ),
        for (final p in [
          Routes.activity,
          Routes.budgetByIdPath,
          Routes.billByIdPath,
          Routes.review,
          Routes.inbox,
          Routes.insights,
        ])
          GoRoute(path: p, builder: (_, s) => screen(s.uri.toString())),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routerProvider.overrideWithValue(router),
          insightsRepositoryProvider.overrideWithValue(insights),
          unreadInsightsCountProvider.overrideWith((ref) async => 0),
          insightsProvider.overrideWith((ref) async => const <Insight>[]),
        ],
        child: Consumer(
          builder: (context, r, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(routerConfig: router, scaffoldMessengerKey: rootMessengerKey);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  tearDown(() {
    NotificationRouter.instance
      ..clear()
      ..isReady = (_) => true;
  });

  group('targets', () {
    test('every target opens its screen', () {
      expect(_to({'target': 'budget', 'target_id': 'b1'}), Routes.budgetById('b1'));
      expect(_to({'target': 'budget'}), Routes.budgets);
      expect(_to({'target': 'loan', 'target_id': 'l1'}), Routes.loanById('l1'));
      expect(_to({'target': 'goal', 'target_id': 'g1'}), Routes.goalById('g1'));
      expect(_to({'target': 'investment', 'target_id': 'i1'}), Routes.investmentById('i1'));
      expect(_to({'target': 'bill', 'target_id': 'p1'}), Routes.billById('p1'));
      expect(_to({'target': 'bill'}), Routes.plan);
      expect(_to({'target': 'daily_summary', 'target_id': 's1'}), Routes.dailySummaryById('s1'));
      expect(_to({'target': 'transaction', 'target_id': 't1'}), Routes.transactionById('t1'));
      expect(_to({'target': 'review', 'target_id': 't2'}), '${Routes.review}?highlight=t2');
      expect(_to({'target': 'inbox_sms', 'target_id': 'm1'}), '${Routes.inbox}?item=m1&kind=sms');
      expect(_to({'target': 'inbox_receipt', 'target_id': 'r1'}), '${Routes.inbox}?item=r1&kind=receipt');
      expect(_to({'target': 'export'}), Routes.exports);
      expect(_to({'target': 'audit_export', 'target_id': 'e1'}), '${Routes.adminAudit}?export=e1');
      expect(_to({'target': 'subscription'}), Routes.subscription);
      expect(_to({'target': 'insight', 'target_id': 'n1'}), Routes.notificationDetailFor('n1'));
      expect(_to({'target': 'add_transaction'}), Routes.addTransaction);
      expect(destinationFor({'target': 'home'}).tab, isTrue);
      final activity = destinationFor({'target': 'activity'});
      expect(activity.location, Routes.activity);
      expect(activity.tab, isTrue);
    });

    test('activity params become filters, flat (push) or nested (notification list)', () {
      final flat = activityQueryFrom({
        'category_id': 'c1',
        'from': '2026-11-02',
        'to': '2026-11-08',
        'tx_type': 'expense',
      });
      expect(flat.categoryId, 'c1');
      expect(flat.from, DateTime(2026, 11, 2));
      expect(flat.to, DateTime(2026, 11, 8));
      expect(flat.type, 'expense');
      final nested = activityQueryFrom({
        'params': {'category_id': 'c2', 'period_start': '2026-10-01'},
      });
      expect(nested.categoryId, 'c2');
      expect(nested.from, DateTime(2026, 10, 1));
      expect(nested.type, isNull);
    });

    test('an unknown target falls back to the type', () {
      expect(_to({'target': 'something_new', 'type': 'budget_alert', 'budget_id': 'b9'}), Routes.budgetById('b9'));
    });
  });

  group('type fallback (older payloads)', () {
    test('types map to the same screens', () {
      expect(_to({'type': 'budget_alert', 'budget_id': 'b1'}), Routes.budgetById('b1'));
      expect(_to({'type': 'budget_alert'}), Routes.budgets);
      expect(_to({'type': 'bill_due', 'recurring_pattern_id': 'p1'}), Routes.billById('p1'));
      expect(_to({'type': 'loan_repayment_due', 'loan_id': 'l1'}), Routes.loanById('l1'));
      expect(_to({'type': 'investment_payout', 'investment_id': 'i1'}), Routes.investmentById('i1'));
      expect(_to({'type': 'savings_opportunity', 'goal_id': 'g1'}), Routes.goalById('g1'));
      expect(_to({'type': 'daily_summary', 'summary_id': 's1'}), Routes.dailySummaryById('s1'));
      expect(_to({'type': 'daily_summary'}), Routes.dailySummaries);
      expect(_to({'type': 'summary'}), Routes.dailySummaries);
      expect(_to({'type': 'export'}), Routes.exports);
      expect(_to({'type': 'audit_export_ready', 'export_id': 'e1'}), '${Routes.adminAudit}?export=e1');
      expect(_to({'type': 'ai_unavailable'}), Routes.addTransaction);
      expect(_to({'type': 'inbox', 'item_type': 'transaction'}), Routes.review);
      expect(_to({'type': 'inbox', 'item_type': 'sms'}), Routes.inbox);
      expect(_to({'type': 'payment_failed'}), Routes.subscription);
      expect(_to({'type': 'announcement', 'insight_id': 'n1'}), Routes.notificationDetailFor('n1'));
      expect(_to({'type': 'whatever', 'insight_id': 'n2'}), Routes.notificationDetailFor('n2'));
      expect(_to({'type': 'whatever'}), Routes.insights);
    });

    test('a spending spike opens Activity on expenses, with its category and week', () {
      final d = destinationFor({
        'type': 'spending_spike',
        'category_id': 'c1',
        'period_start': '2026-11-02',
        'period_end': '2026-11-08',
      });
      expect(d.location, Routes.activity);
      expect(d.tab, isTrue);
      expect(d.activityFilter?.type, 'expense');
      expect(d.activityFilter?.categoryId, 'c1');
      expect(d.activityFilter?.from, DateTime(2026, 11, 2));
      expect(d.activityFilter?.to, DateTime(2026, 11, 8));
    });
  });

  group('notification-centre pills', () {
    Insight insight(String type, {String? target, String? targetId, Map<String, dynamic> params = const {}}) =>
        Insight.fromJson({
          'id': 'n1',
          'type': type,
          'title': 't',
          'body': 'b',
          'target': target,
          'target_id': targetId,
          'params': params,
        });

    test('a budget alert with a target opens that budget', () {
      final a = actionFor(insight('budget_alert', target: 'budget', targetId: 'b1'));
      expect(a.route, Routes.budgetById('b1'));
      expect(a.labelKey, 'notifications2.action.budget');
      expect(a.data['insight_id'], 'n1');
    });

    test('a spike with a target opens Activity with its filters', () {
      final a = actionFor(
        insight(
          'spending_spike',
          target: 'activity',
          params: {'category_id': 'c1', 'from': '2026-11-02', 'to': '2026-11-08', 'tx_type': 'expense'},
        ),
      );
      expect(a.route, Routes.activity);
      expect(a.push, isFalse);
      expect(a.labelKey, 'notifications2.action.spending');
      expect(a.destination.activityFilter?.categoryId, 'c1');
      expect(a.destination.activityFilter?.from, DateTime(2026, 11, 2));
    });
  });

  group('opening', () {
    testWidgets('opening a spike sets the Activity filters and marks the notification read', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      NotificationRouter.instance.isReady = (_) => true;
      NotificationRouter.instance.open(h.ref, {
        'target': 'activity',
        'insight_id': 'n7',
        'category_id': 'c1',
        'from': '2026-11-02',
        'to': '2026-11-08',
        'tx_type': 'expense',
      });
      await tester.pumpAndSettle();
      expect(h.location, Routes.activity);
      final q = h.container.read(activityFilterProvider);
      expect(q.categoryId, 'c1');
      expect(q.type, 'expense');
      expect(q.from, DateTime(2026, 11, 2));
      expect(q.to, DateTime(2026, 11, 8));
      expect(h.insights.read, ['n7']);
    });

    testWidgets('signed out (cold start): waits, then opens after sign-in', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      var ready = false;
      NotificationRouter.instance.isReady = (_) => ready;
      NotificationRouter.instance.open(h.ref, {'target': 'budget', 'target_id': 'b1'});
      await tester.pumpAndSettle();
      expect(h.location, Routes.home);
      expect(NotificationRouter.instance.pending, isNotNull);

      // The shell appears before onboarding / income setup is done: still waits.
      NotificationRouter.instance.flushPending(h.ref);
      await tester.pumpAndSettle();
      expect(h.location, Routes.home);

      ready = true;
      NotificationRouter.instance.flushPending(h.ref);
      await tester.pumpAndSettle();
      expect(h.location, Routes.budgetById('b1'));
      expect(NotificationRouter.instance.pending, isNull);
    });

    testWidgets('sign-out forgets what was waiting', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      NotificationRouter.instance.isReady = (_) => false;
      NotificationRouter.instance.open(h.ref, {'target': 'bill', 'target_id': 'p1'});
      NotificationRouter.instance.clear();
      NotificationRouter.instance.isReady = (_) => true;
      NotificationRouter.instance.flushPending(h.ref);
      await tester.pumpAndSettle();
      expect(h.location, Routes.home);
    });

    testWidgets('review and inbox targets carry the item', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      NotificationRouter.instance.open(h.ref, {'target': 'review', 'target_id': 't9'});
      await tester.pumpAndSettle();
      expect(h.location, '${Routes.review}?highlight=t9');
    });
  });

  group('foreground banner', () {
    testWidgets('shows the push with View, which opens it; it hides itself after 6 s', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      showPushBanner(
        title: 'Transport budget at 85%',
        body: 'MK 29,750 of MK 35,000',
        onView: () => NotificationRouter.instance.open(h.ref, {'target': 'budget', 'target_id': 'b1'}),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('push-banner')), findsOneWidget);
      expect(find.text('Transport budget at 85%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('push-banner-view')));
      await tester.pumpAndSettle();
      expect(h.location, Routes.budgetById('b1'));
      expect(find.byKey(const ValueKey('push-banner')), findsNothing);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('goes away by itself', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      showPushBanner(title: 'Hello', onView: () {});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('push-banner')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('push-banner')), findsNothing);
    });
  });
}
