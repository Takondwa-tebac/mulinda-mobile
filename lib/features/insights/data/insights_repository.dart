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
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String? createdAt;

  String get date => (createdAt ?? '').split('T').first;

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
        id: j['id'].toString(),
        type: j['type']?.toString() ?? 'summary',
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        isRead: j['is_read'] == true,
        createdAt: j['created_at']?.toString(),
      );
}

class InsightsRepository {
  InsightsRepository(this._dio);

  final Dio _dio;

  Future<List<Insight>> list({bool unread = false}) async {
    try {
      final res = await _dio.get('/v1/insights', queryParameters: {
        if (unread) 'unread': 1,
        'per_page': 50,
      });
      final list = (res.data['data'] as List?) ?? const [];
      return list.map((e) => Insight.fromJson((e as Map).cast<String, dynamic>())).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
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

final insightsRepositoryProvider =
    Provider<InsightsRepository>((ref) => InsightsRepository(ref.read(dioProvider)));

final insightsProvider =
    FutureProvider.autoDispose<List<Insight>>((ref) => ref.read(insightsRepositoryProvider).list());

/// Unread count for the Home bell badge (0 while loading/errored).
final unreadInsightsCountProvider = FutureProvider.autoDispose<int>(
    (ref) async => (await ref.read(insightsRepositoryProvider).list(unread: true)).length);
