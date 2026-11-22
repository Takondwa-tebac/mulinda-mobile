import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import 'analytics_models.dart';

/// The analytics reports endpoints (`/v1/analytics/...`) plus the report
/// context of one transaction. GET responses go through the offline cache
/// like every other read, so reports seen before still open offline.
class AnalyticsRepository {
  AnalyticsRepository(this._dio);

  final Dio _dio;

  Future<AnalyticsSummary> summary(PeriodSelection period) async =>
      AnalyticsSummary.fromJson(await _get('/v1/analytics/summary', period.toParams()));

  Future<CategoryBreakdown> categories(PeriodSelection period, {ReportKind kind = ReportKind.expense}) async =>
      CategoryBreakdown.fromJson(await _get('/v1/analytics/categories', {...period.toParams(), 'kind': kind.name}));

  /// [id] is a category id or `uncategorised`.
  Future<CategoryDetail> categoryDetail(String id, PeriodSelection period, {ReportKind kind = ReportKind.expense}) async =>
      CategoryDetail.fromJson(
        await _get('/v1/analytics/categories/${Uri.encodeComponent(id)}', {...period.toParams(), 'kind': kind.name}),
      );

  /// The `context` block of a transaction for [period], or null when the
  /// server did not send one.
  /// `context_period` takes the same `offset` (and `from`/`to` for custom) as
  /// the report endpoints.
  Future<TxnContext?> transactionContext(String id, PeriodSelection period) async {
    final p = period.toParams();
    final data = await _get('/v1/transactions/$id', {
      'context_period': p['period']!,
      if (p['offset'] != null) 'offset': p['offset']!,
      if (p['from'] != null) 'from': p['from']!,
      if (p['to'] != null) 'to': p['to']!,
    });
    return TxnContext.parse(data['context']);
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      final data = res.data is Map ? (res.data as Map)['data'] : null;
      return data is Map ? data.cast<String, dynamic>() : const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) => AnalyticsRepository(ref.read(dioProvider)));

/// Key of a category breakdown.
typedef BreakdownKey = ({PeriodSelection period, ReportKind kind});

/// Key of a category detail.
typedef CategoryDetailKey = ({String id, PeriodSelection period, ReportKind kind});

/// Key of a transaction's report context.
typedef TxnContextKey = ({String id, PeriodSelection period});

final analyticsSummaryProvider = FutureProvider.autoDispose.family<AnalyticsSummary, PeriodSelection>(
  (ref, period) => ref.read(analyticsRepositoryProvider).summary(period),
);

final analyticsCategoriesProvider = FutureProvider.autoDispose.family<CategoryBreakdown, BreakdownKey>(
  (ref, key) => ref.read(analyticsRepositoryProvider).categories(key.period, kind: key.kind),
);

final analyticsCategoryDetailProvider = FutureProvider.autoDispose.family<CategoryDetail, CategoryDetailKey>(
  (ref, key) => ref.read(analyticsRepositoryProvider).categoryDetail(key.id, key.period, kind: key.kind),
);

final transactionContextProvider = FutureProvider.autoDispose.family<TxnContext?, TxnContextKey>(
  (ref, key) => ref.read(analyticsRepositoryProvider).transactionContext(key.id, key.period),
);

/// The first few transactions behind a report (same period and filters as the
/// figure above them), for the "Payments" list on a report.
final reportTransactionsProvider = FutureProvider.autoDispose.family<TxnPage, TxnQuery>(
  (ref, query) => ref.read(activityRepositoryProvider).transactionsPage(query, perPage: 5),
);

/// The period Home's analytics block shows (the owner's default is the last
/// 30 days). Kept for the session.
final homePeriodProvider = StateProvider<PeriodSelection>((ref) => PeriodSelection.defaultPeriod);

/// Chart or table, remembered per report for the session (true = table).
final reportTableViewProvider = StateProvider.family<bool, String>((ref, report) => false);

/// Reload every report (after a new or edited transaction, a sync, or a pull
/// to refresh). Works with a `Ref`, `WidgetRef` or `ProviderContainer`.
void invalidateAnalytics(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(analyticsSummaryProvider);
  invalidate(analyticsCategoriesProvider);
  invalidate(analyticsCategoryDetailProvider);
  invalidate(transactionContextProvider);
  invalidate(reportTransactionsProvider);
}
