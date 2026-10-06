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

  Future<Map<String, dynamic>> goalDetail(String id) => _get('/v1/goals/$id');
  Future<Map<String, dynamic>> loanDetail(String id) => _get('/v1/loans/$id');

  // ---- Mutations -----------------------------------------------------------

  Future<void> createGoal(Map<String, dynamic> data) => _post('/v1/goals', data);
  Future<void> updateGoal(String id, Map<String, dynamic> data) => _put('/v1/goals/$id', data);
  Future<void> deleteGoal(String id) => _delete('/v1/goals/$id');
  Future<void> contributeGoal(String id, Map<String, dynamic> data) => _post('/v1/goals/$id/contributions', data);
  Future<void> updateGoalContribution(String goalId, String contributionId, Map<String, dynamic> data) =>
      _put('/v1/goals/$goalId/contributions/$contributionId', data);
  Future<void> deleteGoalContribution(String goalId, String contributionId) =>
      _delete('/v1/goals/$goalId/contributions/$contributionId');

  Future<void> createBudget(Map<String, dynamic> data) => _post('/v1/budgets', data);
  Future<void> updateBudget(String id, Map<String, dynamic> data) => _put('/v1/budgets/$id', data);
  Future<void> deleteBudget(String id) => _delete('/v1/budgets/$id');

  Future<void> createLoan(Map<String, dynamic> data) => _post('/v1/loans', data);
  Future<void> updateLoan(String id, Map<String, dynamic> data) => _put('/v1/loans/$id', data);
  Future<void> deleteLoan(String id) => _delete('/v1/loans/$id');
  Future<void> repayLoan(String id, Map<String, dynamic> data) => _post('/v1/loans/$id/repayments', data);
  Future<void> updateLoanRepayment(String loanId, String repaymentId, Map<String, dynamic> data) =>
      _put('/v1/loans/$loanId/repayments/$repaymentId', data);
  Future<void> deleteLoanRepayment(String loanId, String repaymentId) =>
      _delete('/v1/loans/$loanId/repayments/$repaymentId');

  Future<void> createInvestment(Map<String, dynamic> data) => _post('/v1/investments', data);
  Future<void> updateInvestment(String id, Map<String, dynamic> data) => _put('/v1/investments/$id', data);
  Future<void> deleteInvestment(String id) => _delete('/v1/investments/$id');

  Future<void> createProject(Map<String, dynamic> data) => _post('/v1/projects', data);
  Future<void> updateProject(String id, Map<String, dynamic> data) => _put('/v1/projects/$id', data);
  Future<void> deleteProject(String id) => _delete('/v1/projects/$id');

  Future<void> _post(String path, Map<String, dynamic> data) => _send(() => _dio.post(path, data: data));
  Future<void> _put(String path, Map<String, dynamic> data) => _send(() => _dio.put(path, data: data));
  Future<void> _delete(String path) => _send(() => _dio.delete(path));
  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await _dio.get(path);
      return (res.data['data'] as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> _send(Future<Response> Function() call) async {
    try {
      await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---- Reads ----------------------------------------------------------------

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

final goalDetailProvider = FutureProvider.family.autoDispose<Map<String, dynamic>, String>(
  (ref, id) => ref.read(planRepositoryProvider).goalDetail(id),
);

final loanDetailProvider = FutureProvider.family.autoDispose<Map<String, dynamic>, String>(
  (ref, id) => ref.read(planRepositoryProvider).loanDetail(id),
);

final goalContributionsProvider = FutureProvider.family.autoDispose<List<GoalContribution>, String>(
  (ref, goalId) async {
    final detail = await ref.read(goalDetailProvider(goalId).future);
    final contributionsJson = detail['contributions'] as List? ?? [];
    return contributionsJson
        .map((e) => GoalContribution.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  },
);

final loanRepaymentsProvider = FutureProvider.family.autoDispose<List<LoanRepayment>, String>(
  (ref, loanId) async {
    final detail = await ref.read(loanDetailProvider(loanId).future);
    final repaymentsJson = detail['repayments'] as List? ?? [];
    return repaymentsJson
        .map((e) => LoanRepayment.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  },
);
