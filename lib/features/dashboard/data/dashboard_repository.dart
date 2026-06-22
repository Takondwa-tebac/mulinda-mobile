import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'dashboard_models.dart';

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  Future<DashboardSummary> fetch() async {
    try {
      final res = await _dio.get('/v1/dashboard');
      return DashboardSummary.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final dashboardRepositoryProvider =
    Provider<DashboardRepository>((ref) => DashboardRepository(ref.read(dioProvider)));

/// The dashboard summary; refresh with `ref.invalidate(dashboardProvider)`.
final dashboardProvider = FutureProvider.autoDispose<DashboardSummary>(
  (ref) => ref.read(dashboardRepositoryProvider).fetch(),
);
