import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';

class CoachChartRepository {
  const CoachChartRepository(this._dio);

  final Dio _dio;

  static const _endpoints = {
    'category_breakdown': '/v1/coach/charts/category-breakdown',
    'account_balances': '/v1/coach/charts/account-balances',
    'spending_summary': '/v1/coach/charts/spending-summary',
    'savings_rule': '/v1/coach/charts/savings-rule',
  };

  /// Fetch chart data for [kind] with optional [params].
  /// Returns null on unknown kind or network failure (non-fatal).
  Future<Map<String, dynamic>?> fetchChart(
    String kind, {
    Map<String, dynamic> params = const {},
  }) async {
    final endpoint = _endpoints[kind];
    if (endpoint == null) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: params.isEmpty ? null : params,
      );
      return (res.data?['data'] as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}

final coachChartRepositoryProvider = Provider<CoachChartRepository>(
  (ref) => CoachChartRepository(ref.read(dioProvider)),
);
