import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/offline/offline_cache_interceptor.dart';
import 'support/memory_store.dart';

class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this.results);
  List<ConnectivityResult> results;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Returns a canned JSON body, or fails like a dead network.
class _Adapter implements HttpClientAdapter {
  bool networkUp = true;
  int calls = 0;
  Map<String, dynamic> body = {'data': 'live'};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (!networkUp) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MemoryStore store;
  late _Adapter adapter;
  late _FakeConnectivity connectivity;
  late Dio dio;
  var active = true;
  String? userId = 'u1';
  final servedFromCache = <DateTime>[];
  var liveCount = 0;

  setUp(() {
    store = MemoryStore();
    adapter = _Adapter();
    connectivity = _FakeConnectivity([ConnectivityResult.wifi]);
    active = true;
    userId = 'u1';
    servedFromCache.clear();
    liveCount = 0;
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(OfflineCacheInterceptor(
        store: store,
        isActive: () => active,
        currentUserId: () => userId,
        onServedFromCache: servedFromCache.add,
        onLiveResponse: () => liveCount++,
        connectivity: connectivity,
      ));
  });

  test('cache key is stable regardless of query order', () {
    final a = RequestOptions(path: '/v1/x', queryParameters: {'b': 2, 'a': 1});
    final b = RequestOptions(path: '/v1/x', queryParameters: {'a': 1, 'b': 2});
    expect(OfflineCacheInterceptor.keyFor(a), OfflineCacheInterceptor.keyFor(b));
    expect(OfflineCacheInterceptor.keyFor(a), 'GET /v1/x?a=1&b=2');
  });

  test('online responses are saved, and replayed when the network is down', () async {
    final live = await dio.get('/v1/goals');
    await Future<void>.delayed(Duration.zero); // let the fire-and-forget save finish
    expect(live.data, {'data': 'live'});
    expect(liveCount, 1);
    expect(store.rows.keys, ['u1|GET /v1/goals']);

    adapter.networkUp = false;
    final cached = await dio.get('/v1/goals');
    expect(cached.data, {'data': 'live'});
    expect(cached.extra[kFromCacheExtra], true);
    expect(servedFromCache, hasLength(1));
  });

  test('when the device reports no connectivity it serves the cache without calling the network', () async {
    await dio.get('/v1/goals');
    await Future<void>.delayed(Duration.zero);
    final callsBefore = adapter.calls;

    connectivity.results = [ConnectivityResult.none];
    final cached = await dio.get('/v1/goals');

    expect(cached.extra[kFromCacheExtra], true);
    expect(adapter.calls, callsBefore); // failed fast, no request made
  });

  test('offline with nothing saved surfaces the network error', () async {
    connectivity.results = [ConnectivityResult.none];
    expect(
      () => dio.get('/v1/never-seen'),
      throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.connectionError)),
    );
  });

  test('nothing is saved or replayed while offline mode is off', () async {
    active = false;
    await dio.get('/v1/goals');
    await Future<void>.delayed(Duration.zero);
    expect(store.rows, isEmpty);

    adapter.networkUp = false;
    expect(() => dio.get('/v1/goals'), throwsA(isA<DioException>()));
  });

  test('sensitive endpoints and writes are never cached', () async {
    await dio.get('/v1/auth/me');
    await dio.get('/v1/admin/users');
    await dio.get('/v1/coach/messages');
    await dio.post('/v1/goals', data: {'name': 'x'});
    await Future<void>.delayed(Duration.zero);
    expect(store.rows, isEmpty);
  });

  test('saved data is separated per user', () async {
    await dio.get('/v1/goals');
    await Future<void>.delayed(Duration.zero);

    userId = 'u2';
    connectivity.results = [ConnectivityResult.none];
    expect(() => dio.get('/v1/goals'), throwsA(isA<DioException>()));
  });

  test('a failed live request (server error) does not fall back to the cache', () async {
    await dio.get('/v1/goals');
    await Future<void>.delayed(Duration.zero);

    // 500 is a real answer from the server, not a network failure.
    adapter
      ..networkUp = true
      ..body = {'message': 'boom'};
    final bad = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = _StatusAdapter(500)
      ..interceptors.add(OfflineCacheInterceptor(
        store: store,
        isActive: () => true,
        currentUserId: () => 'u1',
        onServedFromCache: servedFromCache.add,
        onLiveResponse: () => liveCount++,
        connectivity: connectivity,
      ));
    expect(() => bad.get('/v1/goals'), throwsA(isA<DioException>()));
  });
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);
  final int status;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"message":"boom"}', status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}
