import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/subscription/paywall_prompt.dart';
import '../../features/subscription/widgets/paywall_sheet.dart';
import '../analytics/analytics.dart';
import '../env/app_env.dart';
import '../offline/cache_store.dart';
import '../offline/offline_cache_interceptor.dart';
import '../offline/offline_sync_runner.dart';
import '../offline/offline_write_interceptor.dart';
import '../offline/overlay_engine.dart';
import '../offline/prefs.dart';
import '../offline/trusted_clock.dart';
import '../offline/offline_mode.dart';
import '../offline/offline_status.dart';
import '../router/app_router.dart';
import '../storage/token_storage.dart';
import 'client_headers_interceptor.dart';

/// A configured [Dio] instance: base URL, JSON headers, bearer-token injection,
/// 401 handling that clears the stored token, and 402 handling that offers the
/// paywall (see [PaywallPrompter]).
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppEnv.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );

  // App version, platform, OS version and a request id on every call.
  dio.interceptors.add(ClientHeadersInterceptor());

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

  // The server's clock is the truth for offline-mode plan checks.
  dio.interceptors.add(
    InterceptorsWrapper(
      onResponse: (response, handler) {
        final date = response.headers.value('date');
        if (date != null) {
          try {
            TrustedClock.recordServerTime(ref.read(sharedPreferencesProvider), HttpDate.parse(date));
          } catch (_) {}
        }
        handler.next(response);
      },
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
        if (error.response?.statusCode == 402) {
          _offerPaywall(ref, error);
        }
        handler.next(error);
      },
    ),
  );

  // Funnel analytics ride on this client; events wait until someone is signed in.
  Analytics.configure(
    sender: (body) => dio.post('/v1/analytics/events', data: body, options: Options(extra: {'paywall': false})),
    canSend: () => ref.read(currentUserProvider) != null,
  );

  return dio;
});

/// A 402 `subscription_required` / `sms_capture_limit_reached`: refresh the
/// (now stale) entitlements and, when appropriate, offer the paywall with copy
/// for the locked feature. A request can opt out with `extra: {'paywall': false}`
/// when its screen explains the limit itself.
void _offerPaywall(Ref ref, DioException error) {
  final trigger = paywallTriggerFor(error.response?.statusCode, error.response?.data);
  if (trigger == null || error.requestOptions.extra['paywall'] == false) return;

  unawaited(ref.read(authControllerProvider.notifier).refresh());

  final presentation = PaywallPrompter.instance.handle(trigger, method: error.requestOptions.method);
  if (presentation == null) return;

  // After the failing call has returned to its screen, so that screen settles first.
  Future<void>.delayed(const Duration(milliseconds: 400), () {
    if (PaywallPrompter.instance.saveInProgress) return;
    BuildContext? context;
    try {
      context = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
    } catch (_) {
      context = null;
    }
    if (context == null || !context.mounted) return;
    PaywallPrompter.present(
      context,
      trigger,
      presentation,
      (ctx, t) => showPaywall(ctx, entitlement: t.entitlement, surface: 'api_402'),
    );
  });
}
