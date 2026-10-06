import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../env/app_env.dart';
import '../offline/cache_store.dart';
import '../offline/offline_cache_interceptor.dart';
import '../offline/offline_sync_runner.dart';
import '../offline/offline_write_interceptor.dart';
import '../offline/overlay_engine.dart';
import '../offline/offline_mode.dart';
import '../offline/offline_status.dart';
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

  // Offline mode (only for users who turned it on, see OfflineModeController):
  //  * writes to transactions/goals/loans are queued when there is no network;
  //  * reads are served from the saved cache, with queued changes layered on top.
  final overlay = OverlayEngine(mutations: EncryptedCacheStore.instance, cache: EncryptedCacheStore.instance);
  bool offlineActive() => ref.read(offlineModeProvider).active;
  String? userId() => ref.read(currentUserProvider)?.id;

  dio.interceptors.add(
    OfflineWriteInterceptor(
      store: EncryptedCacheStore.instance,
      cache: EncryptedCacheStore.instance,
      overlay: overlay,
      isActive: offlineActive,
      currentUserId: userId,
      onQueued: () => onChangeQueued(ref.container),
    ),
  );

  dio.interceptors.add(
    OfflineCacheInterceptor(
      store: EncryptedCacheStore.instance,
      overlay: overlay,
      versions: EncryptedCacheStore.instance,
      isActive: offlineActive,
      currentUserId: userId,
      onServedFromCache: (at) => Future.microtask(
        () => ref.read(offlineDataProvider.notifier).markCache(at),
      ),
      onLiveResponse: () => Future.microtask(
        () => ref.read(offlineDataProvider.notifier).markLive(),
      ),
    ),
  );

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
