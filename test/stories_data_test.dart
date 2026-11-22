import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/analytics/analytics.dart';
import 'package:mulinda_mobile/core/network/api_exception.dart';
import 'package:mulinda_mobile/core/notifications/notification_router.dart';
import 'package:mulinda_mobile/core/router/routes.dart';
import 'package:mulinda_mobile/features/stories/data/stories_repository.dart';
import 'package:mulinda_mobile/features/stories/data/story_format.dart';
import 'package:mulinda_mobile/features/stories/data/story_models.dart';
import 'package:mulinda_mobile/features/stories/data/story_visibility.dart';

import 'stories_fixtures.dart';

/// Answers each request from [routes] (`METHOD path` to a JSON body or a
/// status code) and records what was asked.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.routes);

  final Map<String, Object> routes;
  final requests = <RequestOptions>[];

  static const _json = {
    Headers.contentTypeHeader: ['application/json'],
  };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final answer = routes['${options.method} ${options.path}'];
    if (answer is int) return ResponseBody.fromString('{"message":"Not yet"}', answer, headers: _json);
    if (answer == null) return ResponseBody.fromString('', 204);
    return ResponseBody.fromString(jsonEncode(answer), 200, headers: _json);
  }

  @override
  void close({bool force = false}) {}
}

(StoriesRepository, FakeServer) _repo(Map<String, Object> routes) {
  final server = FakeServer(routes);
  return (StoriesRepository(Dio()..httpClientAdapter = server), server);
}

void main() {
  group('repository parses the contract payloads', () {
    test('GET stories/month', () async {
      final (repo, server) = _repo({
        'GET /v1/stories/month': {'data': monthJson()},
      });
      final s = await repo.month('2026-10');

      expect(server.requests.single.queryParameters, {'month': '2026-10'});
      expect(s.kind, StoryKind.month);
      expect(s.period.key, '2026-10');
      expect(s.period.month, 10);
      expect(s.period.startsOn, DateTime(2026, 10, 1));
      expect(s.available, isTrue);
      expect(s.messagesRecorded, 182);
      expect(s.transactionsCount, 201);
      expect(s.income!.minorUnits, 31000000);
      expect(s.spending!.minorUnits, 20130000);
      expect(s.keptRatio, 0.35);
      expect(s.topCategories.map((c) => c.name), ['Sent to people', 'Food', 'Transport']);
      expect(s.topCategories.first.slug, 'sent-to-people');
      expect(s.topCategories.first.share, 0.31);
      expect(s.biggestDay!.date, DateTime(2026, 10, 24));
      expect(s.biggestDay!.share, 0.19);
      expect(s.changeVsPrevious!.previousKey, '2026-09');
      expect(s.changeVsPrevious!.isLess, isTrue);
      expect(s.changeVsPrevious!.percent, 12);
      expect(s.budgets!.kept, 3);
      expect(s.budgets!.total, 4);
      expect(s.moneyStyle, MoneyStyle.steadyPlanner);
      expect(s.topCounterparty!.name, 'Thoko');
      expect(s.topMerchant!.count, 7);
      expect(s.goalsReached!.count, 0);
      expect(s.months, isEmpty);
    });

    test('an unavailable month with null fields parses without errors', () async {
      final (repo, _) = _repo({
        // Only these four fields when the month is not available.
        'GET /v1/stories/month': {
          'data': {
            'period': {'type': 'month', 'key': '2026-10', 'starts_on': '2026-10-01', 'ends_on': '2026-10-31'},
            'available': false,
            'messages_recorded': 4,
            'transactions_count': 6,
          },
        },
      });
      final s = await repo.month();
      expect(s.available, isFalse);
      expect(s.messagesRecorded, 4);
      expect(s.income, isNull);
      expect(s.topCategories, isEmpty);
      expect(s.biggestDay, isNull);
      expect(s.changeVsPrevious, isNull);
      expect(s.budgets, isNull);
      expect(s.moneyStyle, isNull);
      expect(s.goalsReached, isNull);
    });

    test('GET stories/year with the year-only fields', () async {
      final (repo, server) = _repo({
        'GET /v1/stories/year': {'data': yearJson()},
      });
      final s = await repo.year(2026);

      expect(server.requests.single.queryParameters, {'year': 2026});
      expect(s.kind, StoryKind.year);
      expect(s.period.year, 2026);
      expect(s.period.month, isNull);
      expect(s.months.map((m) => m.key), ['2026-01', '2026-03']);
      expect(s.months.last.shareOfMax, 1.0);
      expect(s.months.last.month, 3);
      expect(s.biggestMonth, '2026-03');
      expect(s.topMerchant!.topWeekday, 'saturday');
      expect(s.messagesPerDay, 6.1);
      expect(s.goalsReached!.names, ['School fees', 'New phone']);
      expect(s.goalsReached!.saved!.minorUnits, 65000000);
    });

    test('a year before release is a 403 ApiException', () async {
      final (repo, _) = _repo({'GET /v1/stories/year': 403});
      await expectLater(
        repo.year(2026),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('GET stories/year/status', () async {
      final (repo, _) = _repo({
        'GET /v1/stories/year/status': {'data': statusJson},
      });
      final s = await repo.yearStatus();
      expect(s.year, 2026);
      expect(s.countdownFrom, DateTime(2026, 11, 1));
      expect(s.releaseAt!.toUtc(), DateTime.utc(2026, 11, 25, 5));
      expect(s.daysLeft, 3);
      expect(s.ready, isFalse);
      expect(s.viewed, isFalse);
      expect(s.remindersEnabled, isTrue);
    });

    test('POST viewed and PATCH reminders', () async {
      final (repo, server) = _repo({});
      await repo.markYearViewed(year: 2026);
      await repo.setReminders(false);
      expect(server.requests.map((r) => '${r.method} ${r.path}'), [
        'POST /v1/stories/year/viewed',
        'PATCH /v1/stories/reminders',
      ]);
      expect(server.requests.first.data, {'year': 2026});
      expect(server.requests.last.data, {'enabled': false});
    });
  });

  group('money style', () {
    test('every slug maps to its own title and description key', () {
      const slugs = ['steady_planner', 'saver', 'family_builder', 'foodie', 'explorer', 'everyday_manager'];
      for (final slug in slugs) {
        final style = MoneyStyle.fromSlug(slug)!;
        expect(style.slug, slug);
        expect(style.titleKey, 'stories.style.$slug.title');
        expect(style.descriptionKey, 'stories.style.$slug.body');
      }
      expect(MoneyStyle.values.map((s) => s.slug).toSet(), slugs.toSet());
      expect(MoneyStyle.values.map((s) => s.icon).toSet(), hasLength(slugs.length));
    });

    test('a missing or unknown slug has no style (the slide is left out)', () {
      expect(MoneyStyle.fromSlug(null), isNull);
      expect(MoneyStyle.fromSlug('big_spender'), isNull);
    });
  });

  group('home card windows', () {
    final october = MoneyStory.fromJson(monthJson());

    test('the month card shows from the 1st to the 7th', () {
      for (var day = 1; day <= 7; day++) {
        expect(showMonthReadyCard(now: DateTime(2026, 11, day, 9), story: october, opened: false), isTrue, reason: 'day $day');
      }
      expect(showMonthReadyCard(now: DateTime(2026, 11, 8), story: october, opened: false), isFalse);
      expect(showMonthReadyCard(now: DateTime(2026, 11, 30), story: october, opened: false), isFalse);
    });

    test('the month card hides once opened, when not available, or for another month', () {
      final now = DateTime(2026, 11, 2);
      expect(showMonthReadyCard(now: now, story: october, opened: true), isFalse);
      expect(showMonthReadyCard(now: now, story: MoneyStory.fromJson(monthJson(available: false)), opened: false), isFalse);
      expect(showMonthReadyCard(now: now, story: null, opened: false), isFalse);
      expect(
        showMonthReadyCard(now: now, story: MoneyStory.fromJson(monthJson(key: '2026-09')), opened: false),
        isFalse,
      );
      // January offers December of the year before.
      expect(latestMonthKey(DateTime(2027, 1, 3)), '2026-12');
    });

    YearStoryStatus status({bool ready = false, bool viewed = false, int year = 2026}) =>
        YearStoryStatus.fromJson({...statusJson, 'ready': ready, 'viewed': viewed, 'year': year});

    test('the countdown runs from countdown_from until release', () {
      expect(yearCardFor(now: DateTime(2026, 10, 31, 23), status: status()), YearCard.none);
      expect(yearCardFor(now: DateTime(2026, 11, 1, 0, 5), status: status()), YearCard.countdown);
      expect(yearCardFor(now: DateTime(2026, 11, 24), status: status()), YearCard.countdown);
    });

    test('"It\'s here" from release until watched', () {
      expect(yearCardFor(now: DateTime(2026, 11, 25, 9), status: status(ready: true)), YearCard.ready);
      expect(yearCardFor(now: DateTime(2026, 12, 20), status: status(ready: true)), YearCard.ready);
      expect(yearCardFor(now: DateTime(2026, 11, 26), status: status(ready: true, viewed: true)), YearCard.none);
    });

    test('nothing without a status, or in another year', () {
      expect(yearCardFor(now: DateTime(2026, 11, 20), status: null), YearCard.none);
      expect(yearCardFor(now: DateTime(2027, 1, 2), status: status(ready: true)), YearCard.none);
    });
  });

  group('show amounts', () {
    final s = MoneyStory.fromJson(monthJson());

    test('hidden: percentages; shown: formatted amounts', () {
      final hidden = InOutFigures.of(s, amounts: false)!;
      expect(hidden.inLabel, '100%');
      expect(hidden.outLabel, '65%');
      final shown = InOutFigures.of(s, amounts: true)!;
      expect(shown.inLabel, 'MK 310,000');
      expect(shown.outLabel, 'MK 201,300');
      expect(shown.outBar, closeTo(0.649, 0.001));
      expect(hidden.outBar, shown.outBar);

      final food = s.topCategories[1];
      expect(categoryValue(food, amounts: false), '24%');
      expect(categoryValue(food, amounts: true), 'MK 48,200');
      expect(biggestDayValue(s.biggestDay!, amounts: false), '19%');
      expect(biggestDayValue(s.biggestDay!, amounts: true), 'MK 38,500');
    });

    test('spending above income: spending is the full bar', () {
      final over = MoneyStory.fromJson({...monthJson(), 'income': money(100000), 'spending': money(130000)});
      final f = InOutFigures.of(over, amounts: false)!;
      expect(f.outLabel, '100%');
      expect(f.inLabel, '77%');
      expect(f.inBar, closeTo(0.769, 0.001));
    });

    test('no income and no spending: nothing to compare', () {
      final none = MoneyStory.fromJson({...monthJson(), 'income': money(0), 'spending': money(0)});
      expect(InOutFigures.of(none, amounts: false), isNull);
    });

    test('category bars are relative to the biggest; year shares from the months', () {
      expect(categoryBars(s.topCategories).first, 1.0);
      expect(categoryBars(s.topCategories)[2], closeTo(0.516, 0.001));
      final y = MoneyStory.fromJson(yearJson());
      // 200,000 of 201,300 spent.
      expect(biggestMonthShare(y), closeTo(0.9935, 0.0001));
      expect(groupCount(1846), '1,846');
      expect(groupCount(182), '182');
    });
  });

  group('push and analytics', () {
    test('story push data opens the story', () {
      expect(destinationFor({'type': 'story', 'story': 'month', 'key': '2026-10'}).location, '/stories/month/2026-10');
      expect(destinationFor({'type': 'story', 'story': 'year', 'key': '2026'}).location, '/stories/year/2026');
      // The API also sends target: home; the story still wins.
      expect(
        destinationFor({'type': 'story', 'story': 'month', 'key': '2026-10', 'target': 'home'}).location,
        '/stories/month/2026-10',
      );
      expect(Routes.storyFor(StoryKind.year, '2026'), '/stories/year/2026');
    });

    test('bad story push data falls back to Insights', () {
      expect(destinationFor({'type': 'story', 'story': 'week', 'key': '2026'}).location, Routes.insights);
      expect(destinationFor({'type': 'story', 'story': 'month', 'key': '2026'}).location, Routes.insights);
      expect(destinationFor({'type': 'story', 'story': 'year'}).location, Routes.insights);
    });

    test('story and referral QR events are allowed, with story and key', () {
      for (final e in [
        'story_shown',
        'story_opened',
        'story_completed',
        'story_shared',
        'story_saved',
        'story_reminders_toggled',
        'referral_qr_saved',
        'referral_qr_shared',
      ]) {
        expect(Analytics.allowedEvents, contains(e));
      }
      expect(Analytics.sanitize({'story': 'month', 'key': '2026-10', 'enabled': true, 'name': 'Thoko'}), {
        'story': 'month',
        'key': '2026-10',
        'enabled': true,
      });
    });
  });
}
