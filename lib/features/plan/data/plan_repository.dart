import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'plan_models.dart';

class PlanRepository {
  PlanRepository(this._dio);

  final Dio _dio;

  /// Fetches the three advisory endpoints in parallel; a failed one degrades
  /// gracefully to null rather than failing the whole hub.
  Future<AdvisorySummary> advisory() async {
    final results = await Future.wait([
      _safe('/v1/savings-rule'),
      _safe('/v1/creditworthiness'),
      _safe('/v1/investments/readiness'),
    ]);
    return AdvisorySummary.from(results[0], results[1], results[2]);
  }

  Future<List<GoalItem>> goals() => _list('/v1/goals', GoalItem.fromJson);
  Future<List<BudgetItem>> budgets() => _list('/v1/budgets', BudgetItem.fromJson);
  Future<List<LoanItem>> loans() => _list('/v1/loans', LoanItem.fromJson);
  Future<List<InvestmentItem>> investments() => _list('/v1/investments', InvestmentItem.fromJson);
  Future<List<ProjectItem>> projects() => _list('/v1/projects', ProjectItem.fromJson);

  Future<Map<String, dynamic>?> _safe(String path) async {
    try {
      final res = await _dio.get(path);
      return (res.data['data'] as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<List<T>> _list<T>(String path, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final res = await _dio.get(path);
      final list = (res.data['data'] as List?) ?? const [];
      return list.map((e) => fromJson((e as Map).cast<String, dynamic>())).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final planRepositoryProvider = Provider<PlanRepository>((ref) => PlanRepository(ref.read(dioProvider)));

final advisoryProvider =
    FutureProvider.autoDispose<AdvisorySummary>((ref) => ref.read(planRepositoryProvider).advisory());
final goalsProvider =
    FutureProvider.autoDispose<List<GoalItem>>((ref) => ref.read(planRepositoryProvider).goals());
final budgetsProvider =
    FutureProvider.autoDispose<List<BudgetItem>>((ref) => ref.read(planRepositoryProvider).budgets());
final loansProvider =
    FutureProvider.autoDispose<List<LoanItem>>((ref) => ref.read(planRepositoryProvider).loans());
final investmentsListProvider =
    FutureProvider.autoDispose<List<InvestmentItem>>((ref) => ref.read(planRepositoryProvider).investments());
final projectsProvider =
    FutureProvider.autoDispose<List<ProjectItem>>((ref) => ref.read(planRepositoryProvider).projects());
