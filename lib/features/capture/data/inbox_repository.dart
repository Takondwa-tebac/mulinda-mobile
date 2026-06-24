import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

/// A pending captured SMS awaiting approval.
class PendingSms {
  const PendingSms({required this.id, this.sender, required this.body, this.parsed});

  final String id;
  final String? sender;
  final String body;
  final Map<String, dynamic>? parsed;

  String? get amount => parsed?['amount']?.toString();
  String? get merchant => parsed?['merchant']?.toString();

  factory PendingSms.fromJson(Map<String, dynamic> json) => PendingSms(
        id: json['id'].toString(),
        sender: json['sender']?.toString(),
        body: json['body']?.toString() ?? '',
        parsed: (json['parsed'] as Map?)?.cast<String, dynamic>(),
      );
}

/// A pending scanned receipt awaiting approval.
class PendingReceipt {
  const PendingReceipt({required this.id, this.imageUrl, this.confidence, this.parsed});

  final String id;
  final String? imageUrl;
  final num? confidence;
  final Map<String, dynamic>? parsed;

  String? get amount => parsed?['amount']?.toString();
  String? get merchant => parsed?['merchant']?.toString();

  factory PendingReceipt.fromJson(Map<String, dynamic> json) => PendingReceipt(
        id: json['id'].toString(),
        imageUrl: json['image_url']?.toString(),
        confidence: json['confidence'] as num?,
        parsed: (json['parsed'] as Map?)?.cast<String, dynamic>(),
      );
}

class InboxRepository {
  InboxRepository(this._dio);

  final Dio _dio;

  Future<List<PendingSms>> pendingSms() =>
      _list('/v1/sms', PendingSms.fromJson, query: {'status': 'parsed', 'per_page': 50});

  Future<List<PendingReceipt>> pendingReceipts() => _list(
      '/v1/receipt-scans', PendingReceipt.fromJson, query: {'status': 'parsed', 'per_page': 50});

  Future<void> approveSms(String id) => _post('/v1/sms/$id/approve');
  Future<void> rejectSms(String id) => _post('/v1/sms/$id/reject');
  Future<void> approveReceipt(String id) => _post('/v1/receipt-scans/$id/approve');
  Future<void> rejectReceipt(String id) => _post('/v1/receipt-scans/$id/reject');

  Future<void> _post(String path) async {
    try {
      await _dio.post(path);
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

final inboxRepositoryProvider =
    Provider<InboxRepository>((ref) => InboxRepository(ref.read(dioProvider)));

final pendingSmsProvider =
    FutureProvider.autoDispose<List<PendingSms>>((ref) => ref.read(inboxRepositoryProvider).pendingSms());

final pendingReceiptsProvider = FutureProvider.autoDispose<List<PendingReceipt>>(
    (ref) => ref.read(inboxRepositoryProvider).pendingReceipts());

/// Total pending items, for the Activity badge (0 while loading/errored).
final pendingCountProvider = Provider.autoDispose<int>((ref) {
  final sms = ref.watch(pendingSmsProvider).valueOrNull?.length ?? 0;
  final receipts = ref.watch(pendingReceiptsProvider).valueOrNull?.length ?? 0;
  return sms + receipts;
});
