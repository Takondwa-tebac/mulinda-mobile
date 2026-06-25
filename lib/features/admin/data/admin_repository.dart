import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';

class AdminRepository {
  const AdminRepository(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> listUsers({int page = 1, String? search}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/admin/users',
      queryParameters: {
        'page': page,
        'per_page': 20,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return res.data ?? {};
  }

  Future<void> updateUserRoles(String userId, List<String> roles) async {
    await _dio.put('/v1/admin/users/$userId', data: {'roles': roles});
  }

  Future<void> deleteUser(String userId) async {
    await _dio.delete('/v1/admin/users/$userId');
  }

  Future<Map<String, dynamic>> listAudits({int page = 1}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/admin/audits',
      queryParameters: {'page': page, 'per_page': 25},
    );
    return res.data ?? {};
  }

  /// Comp a user a subscription period (admin gift). [period] is a
  /// BillingPeriod value: day | three_day | week | month.
  Future<void> grantCredit({
    required String userId,
    required String period,
    String? reason,
  }) async {
    await _dio.post('/v1/admin/credits', data: {
      'user_id': userId,
      'period': period,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<int> broadcastNotification({
    required String title,
    required String body,
    String? imageUrl,
    List<String>? userIds,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/admin/notifications/broadcast',
      data: {
        'title': title,
        'body': body,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds,
      },
    );
    return (res.data?['sent_to'] as num?)?.toInt() ?? 0;
  }
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.read(dioProvider)),
);
