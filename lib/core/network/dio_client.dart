import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/app_env.dart';
import '../storage/token_storage.dart';

/// A configured [Dio] instance: base URL, JSON headers, bearer-token injection,
/// and 401 handling that clears the stored token.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppEnv.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );

  final tokens = ref.read(tokenStorageProvider);

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Never let a slow/failing secure-storage read block the request from
        // being sent (otherwise the UI spins forever and nothing reaches the
        // server). Time-box it and proceed without a token on failure.
        try {
          final token = await tokens.read().timeout(const Duration(seconds: 5));
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (_) {
          // Proceed unauthenticated — auth endpoints don't need a token anyway.
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await tokens.clear();
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
