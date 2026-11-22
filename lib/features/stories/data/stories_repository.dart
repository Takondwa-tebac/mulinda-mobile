import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'story_models.dart';

/// The "My month in money" and "My year in money" figures and the year
/// countdown (`/v1/stories/...`). The API is the source of truth for every
/// figure a story shows.
class StoriesRepository {
  const StoriesRepository(this._dio);

  final Dio _dio;

  /// `GET stories/month?month=YYYY-MM` (the previous month when [month] is null).
  Future<MoneyStory> month([String? month]) => _story(
    '/v1/stories/month',
    month == null ? null : {'month': month},
  );

  /// `GET stories/year?year=YYYY`. A 403 before the release date.
  Future<MoneyStory> year(int year) => _story('/v1/stories/year', {'year': year});

  /// `GET stories/year/status`.
  Future<YearStoryStatus> yearStatus() async {
    try {
      final res = await _dio.get('/v1/stories/year/status');
      return YearStoryStatus.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST stories/year/viewed`: the year story of [year] was watched.
  Future<void> markYearViewed({int? year}) async {
    try {
      await _dio.post('/v1/stories/year/viewed', data: year == null ? null : {'year': year});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `PATCH stories/reminders`: story push notifications on or off.
  Future<void> setReminders(bool enabled) async {
    try {
      await _dio.patch('/v1/stories/reminders', data: {'enabled': enabled});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<MoneyStory> _story(String path, Map<String, dynamic>? query) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return MoneyStory.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final storiesRepositoryProvider = Provider<StoriesRepository>(
  (ref) => StoriesRepository(ref.read(dioProvider)),
);

/// A month story by key (`2026-10`).
final monthStoryProvider = FutureProvider.autoDispose.family<MoneyStory, String>(
  (ref, key) => ref.read(storiesRepositoryProvider).month(key),
);

/// A year story by year.
final yearStoryProvider = FutureProvider.autoDispose.family<MoneyStory, int>(
  (ref, year) => ref.read(storiesRepositoryProvider).year(year),
);

/// The year countdown; null when it cannot be loaded (nothing is shown then).
final yearStoryStatusProvider = FutureProvider.autoDispose<YearStoryStatus?>((ref) async {
  try {
    return await ref.read(storiesRepositoryProvider).yearStatus();
  } catch (_) {
    return null;
  }
});
