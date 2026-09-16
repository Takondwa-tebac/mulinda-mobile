import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../activity/data/activity_models.dart';
import 'summary_models.dart';

class SummaryRepository {
  SummaryRepository(this._dio);

  final Dio _dio;

  Future<List<DailySummary>> history() async {
    try {
      final res = await _dio.get('/v1/daily-summaries', queryParameters: {'per_page': 60});
      final list = (res.data['data'] as List?) ?? const [];
      return list
          .map((e) => DailySummary.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Compute today's summary on demand (no push) — used to show today's figures
  /// at the top of the history screen before the scheduled notification fires.
  Future<DailySummary?> today() async {
    try {
      final res = await _dio.get('/v1/daily-summaries/today');
      final data = res.data['data'];
      return data is Map ? DailySummary.fromJson(data.cast<String, dynamic>()) : null;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Get a single daily summary with its transactions by ID.
  Future<DailySummaryWithTransactions> getSummaryWithTransactions(String id) async {
    try {
      final res = await _dio.get('/v1/daily-summaries/$id');
      final data = res.data['data'];
      return DailySummaryWithTransactions.fromJson(data.cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final summaryRepositoryProvider =
    Provider<SummaryRepository>((ref) => SummaryRepository(ref.read(dioProvider)));

final dailySummariesProvider = FutureProvider.autoDispose<List<DailySummary>>(
  (ref) => ref.read(summaryRepositoryProvider).history(),
);

/// Daily summary with transactions by ID.
final dailySummaryDetailProvider = FutureProvider.autoDispose.family<DailySummaryWithTransactions, String>(
  (ref, id) => ref.read(summaryRepositoryProvider).getSummaryWithTransactions(id),
);
