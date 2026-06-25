import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'subscription_models.dart';

class SubscriptionRepository {
  const SubscriptionRepository(this._dio);

  final Dio _dio;

  Future<SubscriptionInfo> status() async {
    try {
      final res = await _dio.get('/v1/subscription');
      return SubscriptionInfo.fromJson(
          (res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<PlanOption>> plans() async {
    try {
      final res = await _dio.get('/v1/subscription/plans');
      final list = (res.data['data'] as List?) ?? [];
      return list
          .map((j) => PlanOption.fromJson((j as Map).cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Start a checkout for [period]; returns the pending invoice with checkout_url.
  Future<InvoiceModel> checkout(String period) async {
    try {
      final res = await _dio.post('/v1/subscription/checkout',
          data: {'period': period});
      return InvoiceModel.fromJson(
          (res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<InvoiceModel>> invoices({String? status}) async {
    try {
      final res = await _dio.get('/v1/invoices',
          queryParameters: status != null ? {'status': status} : null);
      final list = (res.data['data'] as List?) ?? [];
      return list
          .map((j) => InvoiceModel.fromJson((j as Map).cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Re-verify an invoice against the gateway and return its settled state.
  Future<InvoiceModel> verify(String invoiceId) async {
    try {
      final res = await _dio.post('/v1/invoices/$invoiceId/verify');
      return InvoiceModel.fromJson(
          (res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<InvoiceModel> cancel(String invoiceId) async {
    try {
      final res = await _dio.post('/v1/invoices/$invoiceId/cancel');
      return InvoiceModel.fromJson(
          (res.data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(ref.read(dioProvider)),
);

/// The plan catalogue (rarely changes).
final plansProvider = FutureProvider<List<PlanOption>>(
  (ref) => ref.read(subscriptionRepositoryProvider).plans(),
);

/// Invoices, optionally filtered by status (Subscriptions screen tabs).
final invoicesProvider =
    FutureProvider.family<List<InvoiceModel>, String?>(
  (ref, status) => ref.read(subscriptionRepositoryProvider).invoices(status: status),
);
