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
///
/// [reminderTapped]: the person already used the reminder button on the
/// countdown, so it is put away until release day. (Reminders are on by
/// default on the server, so `reminders_enabled` alone says nothing.)
YearCard yearCardFor({required DateTime now, required YearStoryStatus? status, bool reminderTapped = false}) {
  if (status == null || status.year != now.year) return YearCard.none;
  if (status.ready) return status.viewed ? YearCard.none : YearCard.ready;
  if (reminderTapped) return YearCard.none;
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

/// The year countdown's reminder button was used on this phone, per account
/// and year, so Home stops showing the countdown until the story is out.
abstract class YearReminderStore {
  static String key(String? userId, int year) => 'story_year_reminder_tapped_${userId ?? '-'}_$year';

  static Future<bool> isTapped(String? userId, int year) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key(userId, year)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markTapped(String? userId, int year) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key(userId, year), true);
    } catch (_) {
      // Best effort: the countdown may show once more.
    }
  }
}

/// Whether the countdown's reminder button was used for [year].
final yearReminderTappedProvider = FutureProvider.autoDispose.family<bool, int>(
  (ref, year) => YearReminderStore.isTapped(ref.watch(currentUserProvider.select((u) => u?.id)), year),
);

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
