import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/clock.dart';
import '../../auth/providers/auth_controller.dart';
import '../../month_card/data/month_figures.dart';
import 'stories_repository.dart';
import 'story_models.dart';

/// Days at the start of a month on which Home offers last month's story.
const monthCardDays = 7;

/// The month story Home offers on [now]: the previous calendar month.
String latestMonthKey(DateTime now) => monthId(previousMonth(now));

/// Whether Home shows "Your (month) in money is ready": from the 1st for
/// [monthCardDays] days, until it is opened, and only when the API says the
/// month is available.
bool showMonthReadyCard({required DateTime now, required MoneyStory? story, required bool opened}) =>
    now.day <= monthCardDays &&
    !opened &&
    story != null &&
    story.available &&
    story.kind == StoryKind.month &&
    story.period.key == latestMonthKey(now);

/// Which year card Home shows.
enum YearCard { none, countdown, ready }

/// The year card for [status] on [now]: the countdown from `countdown_from`
/// until release, then "It's here" until the story is watched (and only in
/// that year).
YearCard yearCardFor({required DateTime now, required YearStoryStatus? status}) {
  if (status == null || status.year != now.year) return YearCard.none;
  if (status.ready) return status.viewed ? YearCard.none : YearCard.ready;
  final from = status.countdownFrom;
  if (from == null) return YearCard.none;
  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime(from.year, from.month, from.day);
  return today.isBefore(start) ? YearCard.none : YearCard.countdown;
}

/// Stories opened on this phone, per account, so Home stops offering them.
abstract class StoryOpenedStore {
  static String _key(String? userId, StoryKind kind, String key) => 'story_opened_${userId ?? '-'}_${kind.name}_$key';

  static Future<bool> isOpened(String? userId, StoryKind kind, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key(userId, kind, key)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markOpened(String? userId, StoryKind kind, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(userId, kind, key), true);
    } catch (_) {
      // Best effort: Home may offer the story once more.
    }
  }
}

/// The month story Home offers, or null (outside the first days of the
/// month, already opened, not available, or not loaded).
final homeMonthStoryProvider = FutureProvider.autoDispose<MoneyStory?>((ref) async {
  final now = ref.watch(clockProvider)();
  if (now.day > monthCardDays) return null;
  final key = latestMonthKey(now);
  final opened = await StoryOpenedStore.isOpened(ref.read(currentUserProvider)?.id, StoryKind.month, key);
  if (opened) return null;
  try {
    final story = await ref.read(storiesRepositoryProvider).month(key);
    return showMonthReadyCard(now: now, story: story, opened: false) ? story : null;
  } catch (_) {
    return null;
  }
});

/// What "My stories" in Insights lists: the latest month when it is
/// available, and the year once it is released.
class MyStories {
  const MyStories({this.month, this.year});

  final MoneyStory? month;
  final YearStoryStatus? year;

  bool get isEmpty => month == null && year == null;
}

final myStoriesProvider = FutureProvider.autoDispose<MyStories>((ref) async {
  final now = ref.watch(clockProvider)();
  final repo = ref.read(storiesRepositoryProvider);
  final results = await Future.wait<Object?>([
    repo.month(latestMonthKey(now)).then<Object?>((s) => s).catchError((_) => null),
    repo.yearStatus().then<Object?>((s) => s).catchError((_) => null),
  ]);
  final month = results[0] as MoneyStory?;
  final year = results[1] as YearStoryStatus?;
  return MyStories(
    month: month != null && month.available ? month : null,
    year: year != null && year.ready ? year : null,
  );
});
