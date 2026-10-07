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

  // Future<Map<String, dynamic>> getUserDetail(String userId) async {
  //   final res = await _dio.get<Map<String, dynamic>>('/v1/admin/users/$userId');
  //   return res.data ?? {};
    
  // }

  Future<Map<String, dynamic>> getUserDetail(String userId) async {
  final res = await _dio.get<Map<String, dynamic>>(
    '/v1/admin/users/$userId',
  );

  final response = res.data ?? {};

  final data = response['data'];

  if (data is Map) {
    return data.cast<String, dynamic>();
  }

  return response;
}

  /// Platform analytics (users, subscribers, revenue, usage). The API caches
  /// the result for a few minutes; [refresh] forces a recompute.
  Future<Map<String, dynamic>> analytics({bool refresh = false}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/admin/analytics',
      queryParameters: {if (refresh) 'refresh': 1},
    );
    final data = res.data?['data'];
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// Switches for features (offline mode…): master switch, rollout percentage, allow-list.
  Future<List<Map<String, dynamic>>> featureFlags() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/admin/features');
    final data = res.data?['data'];
    return data is List ? data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
  }

  Future<Map<String, dynamic>> updateFeatureFlag(String key, {bool? enabled, int? rolloutPercent}) async {
    final res = await _dio.put<Map<String, dynamic>>('/v1/admin/features/$key', data: {
      if (enabled != null) 'enabled': enabled,
      if (rolloutPercent != null) 'rollout_percent': rolloutPercent,
    });
    final data = res.data?['data'];
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
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
    String? imagePath,
    String? imageUrl,
    List<String>? userIds,
  }) async {
    final specific = userIds != null && userIds.isNotEmpty;
    final form = FormData.fromMap({
      'title': title,
      'body': body,
      // Explicit audience so a targeted send can never fall back to everyone.
      'audience': specific ? 'specific' : 'all',
      if (imagePath != null && imagePath.isNotEmpty)
        'image': await MultipartFile.fromFile(imagePath),
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
    });
    if (specific) {
      // Laravel reads repeated `user_ids[]` fields as an array.
      for (final id in userIds) {
        form.fields.add(MapEntry('user_ids[]', id));
      }
    }

    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/admin/notifications/broadcast',
      data: form,
    );
    return (res.data?['sent_to'] as num?)?.toInt() ?? 0;
  }
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.read(dioProvider)),
);
