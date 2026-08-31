import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'export_models.dart';

class ExportRepository {
  ExportRepository(this._dio);

  final Dio _dio;

  /// Request an export. A subscriber gets a Ready export (HTTP 201); a
  /// non-subscriber gets a PendingPayment export with a checkout URL (HTTP 402)
  /// — both are surfaced as an [ExportModel], so 402 is not treated as an error.
  Future<ExportModel> request({
    required String format,
    DateTime? from,
    DateTime? to,
    String? accountId,
  }) async {
    try {
      final res = await _dio.post(
        '/v1/exports',
        data: {
          'format': format,
          'from': ?from?.toIso8601String(),
          'to': ?to?.toIso8601String(),
          'financial_account_id': ?accountId,
        },
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      return ExportModel.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Re-verify a pending export's payment; on success the file is generated.
  Future<ExportModel> verify(String id) async {
    try {
      final res = await _dio.post('/v1/exports/$id/verify');
      return ExportModel.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<ExportModel> show(String id) async {
    try {
      final res = await _dio.get('/v1/exports/$id');
      return ExportModel.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Download the generated file (auth-bearing) to a temp path and return it,
  /// ready to hand to the share sheet.
  Future<File> download(ExportModel export) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/mulinda-records-${export.id}.${export.format}';
      await _dio.download('/v1/exports/${export.id}/download', path);
      return File(path);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final exportRepositoryProvider =
    Provider<ExportRepository>((ref) => ExportRepository(ref.read(dioProvider)));
