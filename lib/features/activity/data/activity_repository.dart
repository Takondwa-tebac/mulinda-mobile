import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'activity_models.dart';

class ActivityRepository {
  ActivityRepository(this._dio);

  final Dio _dio;

  Future<List<Account>> accounts() => _list('/v1/accounts', Account.fromJson);

  Future<List<Category>> categories() => _list('/v1/categories', Category.fromJson);

  Future<List<Txn>> transactions() =>
      _list('/v1/transactions', Txn.fromJson, query: {'per_page': 50});

  /// Full detail for one transaction — includes the source SMS, fee/levy
  /// children, and account, which the list endpoint omits.
  Future<Txn> transaction(String id) async {
    try {
      final res = await _dio.get('/v1/transactions/$id');
      return Txn.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<Txn>> transactionsForAccount(String accountId) => _list(
        '/v1/transactions',
        Txn.fromJson,
        query: {'financial_account_id': accountId, 'per_page': 200},
      );

  Future<void> createTransaction({
    required String accountId,
    required String type,
    required double amount,
    String? categoryId,
    required DateTime occurredAt,
    String? merchant,
    String? notes,
    String? projectId,
  }) async {
    final body = <String, dynamic>{
      'financial_account_id': accountId,
      'type': type,
      'amount': amount,
      'occurred_at': occurredAt.toIso8601String(),
    };
    if (categoryId != null) body['category_id'] = categoryId;
    if (merchant != null && merchant.isNotEmpty) body['merchant'] = merchant;
    if (notes != null && notes.isNotEmpty) body['notes'] = notes;
    if (projectId != null) body['project_id'] = projectId;

    try {
      await _dio.post('/v1/transactions', data: body);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> createAccount({
    required String name,
    required String type,
    double? openingBalance,
    String? currency,
  }) async {
    final body = <String, dynamic>{'name': name, 'type': type};
    if (openingBalance != null) body['opening_balance'] = openingBalance;
    if (currency != null) body['currency'] = currency;

    try {
      await _dio.post('/v1/accounts', data: body);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Transactions auto-recorded from SMS that are awaiting the user's review.
  Future<List<Txn>> reviewTransactions() => _list(
        '/v1/transactions',
        Txn.fromJson,
        query: {'needs_review': 1, 'per_page': 100},
      );

  /// Confirm auto-recorded items — clears the review flag on each (and its
  /// fee/levy children).
  Future<void> confirmTransactions(List<String> ids) async {
    try {
      await _dio.post('/v1/transactions/confirm', data: {'ids': ids});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Soft-delete a selection of transactions (recoverable server-side).
  Future<void> bulkDeleteTransactions(List<String> ids) async {
    try {
      await _dio.post('/v1/transactions/bulk-delete', data: {'ids': ids});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> ingestSms(String smsBody, {String? sender}) async {
    final body = <String, dynamic>{'body': smsBody};
    if (sender != null && sender.isNotEmpty) body['sender'] = sender;

    try {
      await _dio.post('/v1/sms', data: body);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> scanReceipt(String filePath) async {
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath)});
      await _dio.post('/v1/receipt-scans', data: form);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      final list = (res.data['data'] as List?) ?? const [];
      return list.map((e) => fromJson((e as Map).cast<String, dynamic>())).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final activityRepositoryProvider =
    Provider<ActivityRepository>((ref) => ActivityRepository(ref.read(dioProvider)));

final accountsProvider =
    FutureProvider.autoDispose<List<Account>>((ref) => ref.read(activityRepositoryProvider).accounts());

final categoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) => ref.read(activityRepositoryProvider).categories());

final transactionsProvider =
    FutureProvider.autoDispose<List<Txn>>((ref) => ref.read(activityRepositoryProvider).transactions());

/// Transactions belonging to a single account (for the account detail screen).
final accountTransactionsProvider =
    FutureProvider.autoDispose.family<List<Txn>, String>(
  (ref, accountId) => ref.read(activityRepositoryProvider).transactionsForAccount(accountId),
);

/// Auto-recorded SMS transactions awaiting review.
final reviewTransactionsProvider = FutureProvider.autoDispose<List<Txn>>(
  (ref) => ref.read(activityRepositoryProvider).reviewTransactions(),
);

/// Full detail (incl. source SMS + fee/levy) for one transaction.
final transactionDetailProvider = FutureProvider.autoDispose.family<Txn, String>(
  (ref, id) => ref.read(activityRepositoryProvider).transaction(id),
);

/// Count of items needing review — drives the badge on the activity tab.
final reviewCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final items = await ref.watch(reviewTransactionsProvider.future);
  return items.length;
});
