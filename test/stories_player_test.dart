import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/theme/app_colors.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/stories/data/stories_repository.dart';
import 'package:mulinda_mobile/features/stories/data/story_models.dart';
import 'package:mulinda_mobile/features/stories/data/story_visibility.dart';
import 'package:mulinda_mobile/features/stories/screens/story_screen.dart';
import 'package:mulinda_mobile/features/stories/widgets/story_motion.dart';
import 'package:mulinda_mobile/features/stories/widgets/story_player.dart';
import 'package:mulinda_mobile/features/stories/widgets/story_share.dart';
import 'package:mulinda_mobile/features/stories/widgets/story_slides.dart';
import 'package:mulinda_mobile/shared/clock.dart';
import 'package:mulinda_mobile/features/stories/widgets/home_stories_row.dart';
import 'package:mulinda_mobile/features/stories/widgets/story_home_cards.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stories_fixtures.dart';

List<StorySlide> _slides(int n) => [
  for (var i = 0; i < n; i++)
    StorySlide(id: 's$i', background: AppColors.onTeal, builder: (_) => Text('slide $i')),
];

Future<GlobalKey<StoryPlayerState>> _pumpPlayer(WidgetTester tester, {int count = 3, bool reduced = false}) async {
  final key = GlobalKey<StoryPlayerState>();
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduced),
        child: Scaffold(
          body: StoryPlayer(key: key, slides: _slides(count), title: 'My October', onClose: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  return key;
}

/// Let [d] pass in 50 ms frames, as on a phone (a ticker started between
/// frames only counts from the next frame).
Future<void> _run(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 50)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Offset _right(WidgetTester tester) {
  final r = tester.getRect(find.byKey(const ValueKey('story-tap-area')));
  return Offset(r.left + r.width * 0.85, r.center.dy);
}

Offset _left(WidgetTester tester) {
  final r = tester.getRect(find.byKey(const ValueKey('story-tap-area')));
  return Offset(r.left + r.width * 0.1, r.center.dy);
}

void main() {
  group('StoryNav', () {
    test('moves within the slides', () {
      final nav = StoryNav(3);
      expect(nav.back(), isFalse);
      expect(nav.next(), isTrue);
      expect(nav.next(), isTrue);
      expect(nav.isLast, isTrue);
      expect(nav.next(), isFalse);
      expect(nav.index, 2);
      expect(nav.back(), isTrue);
      expect(nav.index, 1);
      nav.restart();
      expect(nav.index, 0);
    });
  });

  group('StoryPlayer', () {
    testWidgets('moves on by itself after 5 s, and stays on the last slide', (tester) async {
      final key = await _pumpPlayer(tester);
      expect(find.text('slide 0'), findsOneWidget);
      await _run(tester, const Duration(milliseconds: 4800));
      expect(key.currentState!.index, 0);
      await _run(tester, const Duration(milliseconds: 400));
      expect(key.currentState!.index, 1);
      expect(find.text('slide 1'), findsOneWidget);
      await _run(tester, const Duration(milliseconds: 5200));
      expect(key.currentState!.index, 2);
      await _run(tester, const Duration(seconds: 12));
      expect(key.currentState!.index, 2);
    });

    testWidgets('tap right for next, left for back', (tester) async {
      final key = await _pumpPlayer(tester);
      await tester.tapAt(_right(tester));
      await tester.pump();
      expect(key.currentState!.index, 1);
      await tester.tapAt(_right(tester));
      await tester.pump();
      expect(key.currentState!.index, 2);
      await tester.tapAt(_right(tester));
      await tester.pump();
      expect(key.currentState!.index, 2);
      await tester.tapAt(_left(tester));
      await tester.pump();
      expect(key.currentState!.index, 1);
      await tester.tapAt(_left(tester));
      await tester.tapAt(_left(tester));
      await tester.pump();
      expect(key.currentState!.index, 0);
    });

    testWidgets('holding pauses, letting go carries on', (tester) async {
      final key = await _pumpPlayer(tester);
      await _run(tester, const Duration(seconds: 2));
      final hold = await tester.startGesture(_right(tester));
      await _run(tester, const Duration(milliseconds: 600));
      expect(key.currentState!.paused, isTrue);
      await _run(tester, const Duration(seconds: 10));
      expect(key.currentState!.index, 0);
      await hold.up();
      await tester.pump();
      expect(key.currentState!.paused, isFalse);
      // The long press did not count as a tap.
      expect(key.currentState!.index, 0);
      await _run(tester, const Duration(milliseconds: 2200));
      expect(key.currentState!.index, 0);
      await _run(tester, const Duration(milliseconds: 600));
      expect(key.currentState!.index, 1);
    });

    testWidgets('Replay starts again from the first slide', (tester) async {
      final key = await _pumpPlayer(tester);
      await tester.tapAt(_right(tester));
      await tester.tapAt(_right(tester));
      await tester.pump();
      expect(key.currentState!.index, 2);
      await tester.tap(find.byKey(const ValueKey('story-replay')));
      await tester.pump();
      expect(key.currentState!.index, 0);
    });

    testWidgets('reduced motion: nothing moves on by itself and nothing animates', (tester) async {
      final key = await _pumpPlayer(tester, reduced: true);
      expect(key.currentState!.reducedMotion, isTrue);
      await tester.pump(const Duration(seconds: 20));
      expect(key.currentState!.index, 0);
      final motion = tester.widget<StoryMotion>(find.byType(StoryMotion));
      expect(motion.reduced, isTrue);
      expect(motion.entrance.value, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      // Taps still move.
      await tester.tapAt(_right(tester));
      await tester.pump();
      expect(key.currentState!.index, 1);
    });
  });

  group('slides', () {
    Widget share(BuildContext _) => const SizedBox();

    test('the full month has the prototype\'s 8 slides, the full year 9', () {
      final month = monthStorySlides(MoneyStory.fromJson(monthJson()), amounts: false, share: share);
      expect(month.map((s) => s.id), [
        'intro',
        'messages',
        'in-out',
        'categories',
        'biggest-day',
        'style',
        'change',
        'share',
      ]);
      expect(month.map((s) => s.background), StoryBackgrounds.month);

      final year = yearStorySlides(MoneyStory.fromJson(yearJson()), amounts: false, share: share);
      expect(year.map((s) => s.id), [
        'intro',
        'messages',
        'months',
        'categories',
        'person',
        'place',
        'goals',
        'style',
        'share',
      ]);
      expect(year.map((s) => s.background), StoryBackgrounds.year);
    });

    test('slides with null data are skipped', () {
      final sparse = MoneyStory.fromJson({
        ...monthJson(),
        'messages_recorded': 0,
        'top_categories': <Object>[],
        'biggest_day': null,
        'change_vs_previous': null,
        'money_style': 'not_a_style',
      });
      expect(monthStorySlides(sparse, amounts: false, share: share).map((s) => s.id), ['intro', 'in-out', 'share']);

      final year = MoneyStory.fromJson({
        ...yearJson(),
        'months': <Object>[],
        'top_counterparty': null,
        'top_merchant': null,
        'goals_reached': {'count': 0, 'names': <String>[]},
      });
      expect(yearStorySlides(year, amounts: false, share: share).map((s) => s.id), [
        'intro',
        'messages',
        'categories',
        'style',
        'share',
      ]);
    });
  });

  group('StoryScreen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('plays the month story; the share slide toggles amounts', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => null),
            monthStoryProvider('2026-10').overrideWith((ref) async => MoneyStory.fromJson(monthJson())),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const StoryScreen(kind: StoryKind.month, periodKey: '2026-10'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(StoryPlayer), findsOneWidget);
      expect(find.text('stories.month.introTitle'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final player = tester.state<StoryPlayerState>(find.byType(StoryPlayer));
      for (var i = 0; i < 7; i++) {
        player.next();
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull, reason: 'slide $i');
      }
      expect(player.index, 7);
      expect(find.byKey(const ValueKey('story-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-share')), findsOneWidget);
      // Month stories have no invite button.
      expect(find.byKey(const ValueKey('story-invite')), findsNothing);

      final toggle = find.byKey(const ValueKey('story-amounts'));
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      // The amounts now show on the card ("spent" and "came in" tiles).
      expect(find.text('MK 201,300'), findsWidgets);

      // Back to the in/out slide: it shows the amounts too.
      for (var i = 0; i < 5; i++) {
        player.back();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('MK 310,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening the year story records it as viewed', (tester) async {
      final repo = _FakeStories();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => null),
            storiesRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: StoryScreen(kind: StoryKind.year, periodKey: '2026')),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(StoryPlayer), findsOneWidget);
      expect(repo.viewed, 1);
      expect(tester.takeException(), isNull);

      final player = tester.state<StoryPlayerState>(find.byType(StoryPlayer));
      for (var i = 0; i < 8; i++) {
        player.next();
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull, reason: 'slide $i');
      }
      expect(player.index, 8);
      expect(find.byKey(const ValueKey('story-invite')), findsOneWidget);
    });

    testWidgets('the share picture is 1080 x 1920 with no names or link on it', (tester) async {
      final story = MoneyStory.fromJson(yearJson());
      final content = ShareCardContent.of(story, amounts: true);
      final everything = [content.heading, content.styleTitle, content.footer, for (final t in content.tiles) ...[t.value, t.label]];
      expect(everything.whereType<String>().any((s) => s.contains('Thoko') || s.contains('http')), isFalse);
      expect(content.tiles.map((t) => t.value), contains('MK 201,300'));
      expect(ShareCardContent.of(story, amounts: false).tiles.map((t) => t.value), isNot(contains('MK 201,300')));

      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: key, child: StoryShareImage(content: content)),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: StoryShareImage.pixelRatio));
      expect(image!.width, 1080);
      expect(image.height, 1920);
      image.dispose();
    });
  });

  group('Home cards', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<_FakeStories> pumpCards(WidgetTester tester, DateTime now, {Map<String, dynamic>? status}) async {
      final repo = _FakeStories(status: status);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            currentUserProvider.overrideWith((ref) => null),
            storiesRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: SingleChildScrollView(child: StoryHomeCards())),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      return repo;
    }

    testWidgets('2 November: last month is ready and the year counts down', (tester) async {
      await pumpCards(tester, DateTime(2026, 11, 2, 9));
      expect(find.byKey(const ValueKey('story-month-ready')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-year-countdown')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-year-ready')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('after the 7th the month card is gone', (tester) async {
      final repo = await pumpCards(tester, DateTime(2026, 11, 8));
      expect(find.byKey(const ValueKey('story-month-ready')), findsNothing);
      // Not even asked for.
      expect(repo.monthCalls, 0);
    });

    testWidgets('an opened month is not offered again', (tester) async {
      SharedPreferences.setMockInitialValues({'story_opened_-_month_2026-10': true});
      await pumpCards(tester, DateTime(2026, 11, 3));
      expect(find.byKey(const ValueKey('story-month-ready')), findsNothing);
    });

    testWidgets('release day shows "It\'s here"', (tester) async {
      await pumpCards(tester, DateTime(2026, 11, 25, 10), status: {...statusJson, 'ready': true, 'days_left': 0});
      expect(find.byKey(const ValueKey('story-year-ready')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-year-countdown')), findsNothing);
    });

    testWidgets('Remind me calls PATCH reminders', (tester) async {
      final repo = await pumpCards(tester, DateTime(2026, 11, 20), status: {...statusJson, 'reminders_enabled': false});
      expect(find.text('stories.home.remindMe'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-remind')));
      await tester.pump();
      await tester.pump();
      expect(repo.reminders, [true]);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      // The choice is made: the countdown steps aside, with a confirmation.
      expect(find.byKey(const ValueKey('story-year-countdown')), findsNothing);
      expect(find.text('stories.home.remindSet'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(YearReminderStore.key(null, 2026)), isTrue);
    });

    testWidgets('turning reminders off keeps the countdown so they can be turned back on', (tester) async {
      final repo = await pumpCards(tester, DateTime(2026, 11, 20));
      expect(find.text('stories.home.remindersOn'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-remind')));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(repo.reminders, [false]);
      expect(find.byKey(const ValueKey('story-year-countdown')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(YearReminderStore.key(null, 2026)), isNull);
    });

    testWidgets('the month card closes with its X', (tester) async {
      await pumpCards(tester, DateTime(2026, 11, 2, 9));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('story-month-ready')),
          matching: find.byKey(const ValueKey('story-card-close')),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('story-month-ready')), findsNothing);
      expect(find.byKey(const ValueKey('story-year-countdown')), findsOneWidget);
    });

    testWidgets('the countdown closes with its X and stays closed', (tester) async {
      await pumpCards(tester, DateTime(2026, 11, 20));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('story-year-countdown')),
          matching: find.byKey(const ValueKey('story-card-close')),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('story-year-countdown')), findsNothing);
      expect(find.text('stories.home.closed'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(YearReminderStore.key(null, 2026)), isTrue);
    });

    testWidgets('the ready card closes with its X', (tester) async {
      await pumpCards(tester, DateTime(2026, 11, 25, 10), status: {...statusJson, 'ready': true, 'days_left': 0});
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('story-year-ready')),
          matching: find.byKey(const ValueKey('story-card-close')),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('story-year-ready')), findsNothing);
    });

    testWidgets('a used reminder button keeps the countdown away', (tester) async {
      SharedPreferences.setMockInitialValues({YearReminderStore.key(null, 2026): true});
      await pumpCards(tester, DateTime(2026, 11, 21));
      expect(find.byKey(const ValueKey('story-year-countdown')), findsNothing);
    });

    testWidgets('release day shows the ready card even after the reminder button was used', (tester) async {
      SharedPreferences.setMockInitialValues({YearReminderStore.key(null, 2026): true});
      await pumpCards(tester, DateTime(2026, 11, 25, 10), status: {...statusJson, 'ready': true, 'days_left': 0});
      expect(find.byKey(const ValueKey('story-year-ready')), findsOneWidget);
    });
  });

  group('Your stories row on Home', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<List<String>> pumpRow(WidgetTester tester, DateTime now, {Map<String, dynamic>? status, bool dark = false}) async {
      final opened = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: SingleChildScrollView(child: Column(children: [StoryHomeCards(), HomeStoriesRow()])),
            ),
          ),
          GoRoute(
            path: '/stories/:story/:key',
            builder: (_, state) {
              opened.add(state.uri.path);
              return const Scaffold(body: Text('story'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            currentUserProvider.overrideWith((ref) => null),
            storiesRepositoryProvider.overrideWithValue(_FakeStories(status: status)),
          ],
          child: MaterialApp.router(theme: dark ? AppTheme.dark : AppTheme.light, routerConfig: router),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      return opened;
    }

    for (final dark in [false, true]) {
      testWidgets('after the 7th last month stays one tap away and opens its story (${dark ? 'dark' : 'light'})', (tester) async {
        final opened = await pumpRow(tester, DateTime(2026, 11, 20), dark: dark);
        expect(find.byKey(const ValueKey('story-month-ready')), findsNothing);
        expect(find.byKey(const ValueKey('home-story-month')), findsOneWidget);
        expect(find.text('stories.home.rowLabel'), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('home-story-month'))).height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('home-story-month')));
        await tester.pumpAndSettle();
        expect(opened, ['/stories/month/2026-10']);
      });
    }

    testWidgets('no second entry while the big month card is up', (tester) async {
      await pumpRow(tester, DateTime(2026, 11, 2));
      expect(find.byKey(const ValueKey('story-month-ready')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-stories')), findsNothing);
    });

    testWidgets('a watched year story is listed with the month', (tester) async {
      final opened = await pumpRow(
        tester,
        DateTime(2026, 11, 26),
        status: {...statusJson, 'ready': true, 'viewed': true, 'days_left': 0},
      );
      expect(find.byKey(const ValueKey('story-year-ready')), findsNothing);
      expect(find.byKey(const ValueKey('home-story-year')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-story-month')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-story-year')));
      await tester.pumpAndSettle();
      expect(opened, ['/stories/year/2026']);
    });

    test('entries leave out what a big card already offers', () {
      final stories = MyStories(
        month: MoneyStory.fromJson(monthJson()),
        year: YearStoryStatus.fromJson({...statusJson, 'ready': true}),
      );
      expect(homeStoryEntries(stories: null, monthCardShown: false, yearCardShown: false), isEmpty);
      expect(
        homeStoryEntries(stories: stories, monthCardShown: false, yearCardShown: false).map((e) => e.kind),
        [StoryKind.year, StoryKind.month],
      );
      expect(
        homeStoryEntries(stories: stories, monthCardShown: true, yearCardShown: true),
        isEmpty,
      );
    });
  });
}

class _FakeStories extends StoriesRepository {
  _FakeStories({Map<String, dynamic>? status}) : _status = status ?? statusJson, super(Dio());

  final Map<String, dynamic> _status;
  int viewed = 0;
  int monthCalls = 0;
  final reminders = <bool>[];

  @override
  Future<MoneyStory> month([String? month]) async {
    monthCalls++;
    return MoneyStory.fromJson(monthJson(key: month ?? '2026-10'));
  }

  @override
  Future<MoneyStory> year(int year) async => MoneyStory.fromJson(yearJson());

  @override
  Future<YearStoryStatus> yearStatus() async => YearStoryStatus.fromJson(_status);

  @override
  Future<void> markYearViewed({int? year}) async => viewed++;

  @override
  Future<void> setReminders(bool enabled) async => reminders.add(enabled);
}
