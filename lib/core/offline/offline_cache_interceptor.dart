import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import 'cache_store.dart';

/// Marker on a [Response.extra] for data that came from the offline cache.
const kFromCacheExtra = 'fromCache';
const kFetchedAtExtra = 'fetchedAtMs';

/// Read-through cache for GET requests, active only while offline mode is on.
///
/// * Online: the request goes to the server as normal and its successful JSON
///   response is saved (encrypted) for later.
/// * Offline (no connectivity, or the request fails for lack of a network): the
///   saved response is returned instead, so every existing screen keeps working
///   with the last data it saw. If nothing was saved the original error stands.
///
/// Writes (POST/PUT/PATCH/DELETE) are never cached or faked — until queued
/// edits exist they fail with the normal network error.
class OfflineCacheInterceptor extends Interceptor {
  OfflineCacheInterceptor({
    required this.store,
    required this.isActive,
    required this.currentUserId,
    required this.onServedFromCache,
    required this.onLiveResponse,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  final CacheStore store;
  final bool Function() isActive;
  final String? Function() currentUserId;
  final void Function(DateTime fetchedAt) onServedFromCache;
  final void Function() onLiveResponse;
  final Connectivity _connectivity;

  /// Endpoints whose responses must never be stored or replayed: credentials,
  /// admin tools, downloads, AI chat and payment flows.
  static const _neverCache = [
    '/v1/auth',
    '/v1/admin',
    '/v1/exports',
    '/v1/coach',
    '/v1/payments',
    '/v1/devices',
  ];

  /// Stable key for a request: method, path and sorted query.
  static String keyFor(RequestOptions o) {
    final query = o.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final q = query.map((e) => '${e.key}=${e.value}').join('&');
    return q.isEmpty ? '${o.method} ${o.path}' : '${o.method} ${o.path}?$q';
  }

  bool _eligible(RequestOptions o) {
    if (o.method != 'GET' || !isActive() || currentUserId() == null) return false;
    return !_neverCache.any(o.path.startsWith);
  }

  static bool _isNetworkFailure(DioException e) =>
      e.response == null &&
      (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.unknown);

  Future<bool> _isOffline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      return false; // can't tell — let the request decide
    }
  }

  Future<Response<dynamic>?> _fromCache(RequestOptions o) async {
    final userId = currentUserId();
    if (userId == null) return null;
    try {
      final hit = await store.get(userId, keyFor(o));
      if (hit == null) return null;
      onServedFromCache(hit.fetchedAt);
      return Response<dynamic>(
        requestOptions: o,
        data: hit.body,
        statusCode: 200,
        extra: {
          kFromCacheExtra: true,
          kFetchedAtExtra: hit.fetchedAt.millisecondsSinceEpoch,
        },
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_eligible(options) && await _isOffline()) {
      // Fail fast instead of waiting out the connect timeout.
      final cached = await _fromCache(options);
      if (cached != null) return handler.resolve(cached, true);
      return handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        ),
        true,
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    if (_eligible(o) && response.statusCode == 200 && response.extra[kFromCacheExtra] != true) {
      final data = response.data;
      final userId = currentUserId();
      if (userId != null && (data is Map || data is List)) {
        // Fire and forget: caching must never slow down or break a request.
        unawaited(store.put(userId, keyFor(o), data).catchError((_) {}));
      }
      onLiveResponse();
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    if (_eligible(o) && _isNetworkFailure(err)) {
      final cached = await _fromCache(o);
      if (cached != null) return handler.resolve(cached);
    }
    handler.next(err);
  }
}
