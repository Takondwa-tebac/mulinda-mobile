import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import 'cache_store.dart';
import 'entity_adapters.dart';
import 'ids.dart';
import 'mutation_store.dart';
import 'overlay_engine.dart';

const _writeMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};
const _kMatch = 'offlineWriteMatch';

/// Lets transactions, goals and loans be added, edited and deleted without a
/// connection (offline mode only).
///
/// * Every such write is given an `Idempotency-Key`, and creates get a
///   client-chosen `id`, so replaying it later can never apply it twice.
/// * With no connection — or while earlier changes are still waiting, so order
///   is preserved — the change is saved to the queue and the caller gets a
///   successful (locally built) answer; the screen shows it straight away via
///   the [OverlayEngine] and marks it "waiting to sync".
/// * Online with an empty queue the request goes out normally; if it then fails
///   for lack of a network it is queued the same way.
class OfflineWriteInterceptor extends Interceptor {
  OfflineWriteInterceptor({
    required this.store,
    required this.cache,
    required this.overlay,
    required this.isActive,
    required this.currentUserId,
    required this.onQueued,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  final MutationStore store;
  final CacheStore cache;
  final OverlayEngine overlay;
  final bool Function() isActive;
  final String? Function() currentUserId;

  /// A change was queued (the caller schedules a sync attempt).
  final void Function() onQueued;
  final Connectivity _connectivity;

  Future<bool> _isOffline() async {
    try {
      final r = await _connectivity.checkConnectivity();
      return r.isEmpty || r.every((e) => e == ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  static bool _isNetworkFailure(DioException e) =>
      e.response == null &&
      (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.unknown);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final userId = currentUserId();
    if (userId == null || !isActive() || !_writeMethods.contains(options.method.toUpperCase())) {
      return handler.next(options);
    }

    final data = options.data;
    final body = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    var match = matchWrite(options.method, options.path, body);
    if (match == null) return handler.next(options);

    // Identifiers that make a later replay safe, attached even when the request
    // goes out live now (it may fail after the server already applied it).
    options.headers['Idempotency-Key'] ??= newUuid();
    if (match.op == 'create' && (body['id'] == null || '${body['id']}'.isEmpty)) {
      body['id'] = newUuid();
      options.data = body;
      match = matchWrite(options.method, options.path, body)!;
    }
    options.extra[_kMatch] = match;

    final queueNotEmpty = await store.count(userId: userId) > 0;
    if (queueNotEmpty || await _isOffline()) {
      return handler.resolve(await _queue(options, match, userId, body), true);
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final match = err.requestOptions.extra[_kMatch];
    final userId = currentUserId();
    if (match is WriteMatch && userId != null && isActive() && _isNetworkFailure(err)) {
      final data = err.requestOptions.data;
      final body = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      return handler.resolve(await _queue(err.requestOptions, match, userId, body));
    }
    handler.next(err);
  }

  Future<Response<dynamic>> _queue(RequestOptions options, WriteMatch match, String userId, Map<String, dynamic> body) async {
    final adapter = adapterFor(match.entity)!;
    final key = options.headers['Idempotency-Key'].toString();

    Map<String, dynamic> effect = const {};
    dynamic answer;
    var status = 200;

    switch (match.op) {
      case 'create':
        final record = await adapter.buildRecord(body, overlay.lookupFor(userId));
        effect = {'record': record};
        answer = {'data': record, 'queued': true};
        status = 201;
      case 'update':
        answer = {
          'data': adapter.applyPatch({'id': match.targetIds.isEmpty ? null : match.targetIds.first}, body),
          'queued': true,
        };
      case 'delete':
        answer = null;
        status = 204;
    }

    // The server rejects an edit/delete whose base version is stale (server wins).
    String? base;
    if (match.op != 'create' && match.targetIds.length == 1) {
      base = await store.version(userId, match.entity, match.targetIds.first);
    }

    await store.enqueue(PendingMutation(
      id: key,
      userId: userId,
      entity: match.entity,
      op: match.op,
      targetIds: match.targetIds,
      method: options.method.toUpperCase(),
      path: options.path,
      body: body,
      baseUpdatedAt: base,
      effect: effect,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    ));
    onQueued();

    return Response<dynamic>(
      requestOptions: options,
      data: answer,
      statusCode: status,
      extra: const {'queued': true},
    );
  }
}
