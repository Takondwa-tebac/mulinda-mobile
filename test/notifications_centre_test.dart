import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mulinda_mobile/core/router/routes.dart';
import 'package:mulinda_mobile/features/insights/data/insights_repository.dart';
import 'package:mulinda_mobile/features/insights/screens/insights_screen.dart';
import 'package:mulinda_mobile/features/insights/widgets/notification_card.dart';

final _now = DateTime.now();

Insight _i(String id, String type, {bool read = false, Duration ago = Duration.zero}) => Insight.fromJson({
  'id': id,
  'type': type,
  'title': 'Title $id',
  'body': 'Body $id',
  'is_read': read,
  'created_at': _now.subtract(ago).toUtc().toIso8601String(),
});

/// Records requests; answers read-all with [readAllStatus].
class _Server implements HttpClientAdapter {
  _Server({this.readAllStatus = 200});

  final int readAllStatus;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls.add('${o.method} ${o.path}');
    final status = o.path.endsWith('/read-all') ? readAllStatus : 200;
    return ResponseBody.fromString(
      jsonEncode(
        status == 200
            ? {
                'data': {'updated': 1, 'unread': 0},
              }
            : {'message': 'Not Found'},
      ),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('kinds and filters', () {
    test('server types map to the filter chips', () {
      expect(groupOf('budget_alert'), InsightFilter.alerts);
      expect(groupOf('spending_spike'), InsightFilter.alerts);
      for (final t in ['bill_due', 'loan_repayment_due', 'investment_contribution_due', 'investment_meeting']) {
        expect(groupOf(t), InsightFilter.dueSoon, reason: t);
      }
      for (final t in ['savings_opportunity', 'investment_payout', 'summary', 'announcement']) {
        expect(groupOf(t), InsightFilter.updates, reason: t);
      }
      expect(groupOf('something_new'), isNull);
    });

    test('unread and kind filters', () {
      final a = _i('a', 'budget_alert');
      expect(matchesFilter(a, InsightFilter.all, isRead: true), isTrue);
      expect(matchesFilter(a, InsightFilter.unread, isRead: false), isTrue);
      expect(matchesFilter(a, InsightFilter.unread, isRead: true), isFalse);
      expect(matchesFilter(a, InsightFilter.alerts, isRead: true), isTrue);
      expect(matchesFilter(a, InsightFilter.updates, isRead: true), isFalse);
    });

    test('actions go to existing screens, the list when there is no single target', () {
      expect(actionFor(_i('1', 'budget_alert')).route, Routes.budgets);
      expect(actionFor(_i('1', 'bill_due')).route, Routes.plan);
      expect(actionFor(_i('1', 'loan_repayment_due')).route, Routes.loans);
      expect(actionFor(_i('1', 'investment_payout')).route, Routes.investments);
      expect(actionFor(_i('1', 'summary')).route, Routes.dailySummaries);
      final spike = actionFor(_i('1', 'spending_spike'));
      expect(spike.route, Routes.activity);
      expect(spike.expenseFilter, isTrue);
      expect(actionFor(_i('1', 'savings_opportunity')).route, Routes.goals);
      expect(actionFor(_i('9', 'announcement')).route, Routes.notificationDetailFor('9'));
    });
  });

  group('day groups', () {
    test('today, yesterday, earlier this week, then by month', () {
      final now = DateTime(2026, 11, 6, 15); // a Friday
      expect(insightGroupLabel(DateTime(2026, 11, 6, 8), now), 'common.today');
      expect(insightGroupLabel(DateTime(2026, 11, 5, 8), now), 'common.yesterday');
      expect(insightGroupLabel(DateTime(2026, 11, 3, 8), now), 'notifications2.earlierThisWeek');
      expect(insightGroupLabel(DateTime(2026, 10, 20), now), 'common.monthLong.10 2026');
    });

    test('consecutive items share a header', () {
      final groups = groupInsights([
        _i('1', 'summary'),
        _i('2', 'summary', ago: const Duration(minutes: 5)),
        _i('3', 'summary', ago: const Duration(days: 40)),
      ], _now);
      expect(groups.first.$2.length, 2);
      expect(groups.length, 2);
    });
  });

  group('the screen', () {
    Future<_Server> pump(WidgetTester tester, List<Insight> items, {int readAllStatus = 200}) async {
      final server = _Server(readAllStatus: readAllStatus);
      final router = GoRouter(
        initialLocation: Routes.insights,
        routes: [
          GoRoute(path: Routes.insights, builder: (_, _) => const InsightsScreen()),
          GoRoute(
            path: Routes.budgets,
            builder: (_, _) => const Scaffold(body: Text('budgets-screen')),
          ),
          GoRoute(
            path: '/notifications/:id',
            builder: (_, _) => const Scaffold(body: Text('detail-screen')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            insightsProvider.overrideWith((ref) async => items),
            unreadInsightsCountProvider.overrideWith((ref) async => 0),
            insightsRepositoryProvider.overrideWithValue(InsightsRepository(Dio()..httpClientAdapter = server)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return server;
    }

    testWidgets('unread cards have a dot and a bold title, read ones do not', (tester) async {
      await pump(tester, [_i('u', 'budget_alert'), _i('r', 'summary', read: true)]);
      expect(find.byKey(const ValueKey('insight-unread-u')), findsOneWidget);
      expect(find.byKey(const ValueKey('insight-unread-r')), findsNothing);
      final bold = tester.widget<Text>(find.byKey(const ValueKey('insight-title-u')));
      final plain = tester.widget<Text>(find.byKey(const ValueKey('insight-title-r')));
      expect(bold.style?.fontWeight, FontWeight.w700);
      expect(plain.style?.fontWeight, FontWeight.w400);
    });

    testWidgets('a filter with nothing in it says so', (tester) async {
      await pump(tester, [_i('r', 'summary', read: true)]);
      await tester.ensureVisible(find.byKey(const ValueKey('insight-filter-alerts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insight-filter-alerts')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insights-filter-empty')), findsOneWidget);
    });

    testWidgets('no notifications at all: all caught up', (tester) async {
      await pump(tester, const []);
      expect(find.byKey(const ValueKey('insights-caught-up')), findsOneWidget);
    });

    testWidgets('the action pill navigates to its screen', (tester) async {
      await pump(tester, [_i('u', 'budget_alert')]);
      await tester.tap(find.byKey(const ValueKey('insight-action-u')));
      await tester.pumpAndSettle();
      expect(find.text('budgets-screen'), findsOneWidget);
    });

    testWidgets('mark all as read uses the bulk endpoint', (tester) async {
      final server = await pump(tester, [_i('a', 'budget_alert'), _i('b', 'summary')]);
      await tester.tap(find.byKey(const ValueKey('mark-all-read')));
      await tester.pumpAndSettle();
      expect(server.calls, ['POST /v1/insights/read-all']);
      expect(find.byKey(const ValueKey('insight-unread-a')), findsNothing);
      expect(find.byKey(const ValueKey('mark-all-read')), findsNothing);
    });

    testWidgets('an older server (404) falls back to marking each one', (tester) async {
      final server = await pump(tester, [_i('a', 'budget_alert'), _i('b', 'summary')], readAllStatus: 404);
      await tester.tap(find.byKey(const ValueKey('mark-all-read')));
      await tester.pumpAndSettle();
      expect(server.calls, ['POST /v1/insights/read-all', 'PATCH /v1/insights/a/read', 'PATCH /v1/insights/b/read']);
      expect(find.byKey(const ValueKey('insight-unread-b')), findsNothing);
    });

    testWidgets('a failure puts the unread state back', (tester) async {
      await pump(tester, [_i('a', 'budget_alert')], readAllStatus: 500);
      await tester.tap(find.byKey(const ValueKey('mark-all-read')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insight-unread-a')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
