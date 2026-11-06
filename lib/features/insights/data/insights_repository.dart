import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

class Insight {
  const Insight({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    this.createdAt,
    this.imageUrl,
    this.details = const {},
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String? createdAt;

  /// Image attached to an admin announcement, if any.
  final String? imageUrl;

  /// Extra structured fields sent with the notification.
  final Map<String, dynamic> details;

  String get date => (createdAt ?? '').split('T').first;

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
    id: j['id'].toString(),
    type: j['type']?.toString() ?? 'summary',
    title: j['title']?.toString() ?? '',
    body: j['body']?.toString() ?? '',
    isRead: j['is_read'] == true,
    createdAt: j['created_at']?.toString(),
    imageUrl: (j['details'] is Map) ? (j['details'] as Map)['image_url']?.toString() : null,
    details: (j['details'] is Map) ? (j['details'] as Map).cast<String, dynamic>() : const {},
  );
}

class InsightsRepository {
  InsightsRepository(this._dio);

  final Dio _dio;

  Future<List<Insight>> list({bool unread = false}) async {
    try {
      final res = await _dio.get('/v1/insights', queryParameters: {if (unread) 'unread': 1, 'per_page': 50});
      final list = (res.data['data'] as List?) ?? const [];
      return list.map((e) => Insight.fromJson((e as Map).cast<String, dynamic>())).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Marks unread notifications as read in one call:
  /// `POST /v1/insights/read-all` with `before` (everything up to when the list
  /// was loaded) or `ids` (just these). Returns the server's unread count.
  Future<int?> markAllRead({DateTime? before, List<String>? ids}) async {
    try {
      final res = await _dio.post(
        '/v1/insights/read-all',
        data: {if (before != null) 'before': before.toUtc().toIso8601String(), 'ids': ?ids},
      );
      final data = res.data is Map ? (res.data as Map)['data'] : null;
      return data is Map ? (data['unread'] as num?)?.toInt() : null;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// [markAllRead], falling back to one `PATCH insights/{id}/read` per id on an
  /// older server without the bulk endpoint (404).
  Future<void> markAllReadOrEach({DateTime? before, required List<String> ids}) async {
    try {
      await markAllRead(before: before, ids: before == null ? ids : null);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      for (final id in ids) {
        await markRead(id);
      }
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _dio.patch('/v1/insights/$id/read');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final insightsRepositoryProvider = Provider<InsightsRepository>((ref) => InsightsRepository(ref.read(dioProvider)));

final insightsProvider = FutureProvider.autoDispose<List<Insight>>(
  (ref) => ref.read(insightsRepositoryProvider).list(),
);

/// Unread count for the Home bell badge (0 while loading/errored).
final unreadInsightsCountProvider = FutureProvider.autoDispose<int>(
  (ref) async => (await ref.read(insightsRepositoryProvider).list(unread: true)).length,
);
