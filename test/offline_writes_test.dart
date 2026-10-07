import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/offline/entity_adapters.dart';
import 'package:mulinda_mobile/core/offline/mutation_store.dart';
import 'package:mulinda_mobile/core/offline/mutation_sync.dart';
import 'package:mulinda_mobile/core/offline/offline_cache_interceptor.dart';
import 'package:mulinda_mobile/core/offline/offline_write_interceptor.dart';
import 'package:mulinda_mobile/core/offline/overlay_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_store.dart';

const acct = '11111111-1111-4111-8111-111111111111';
const cat = '22222222-2222-4222-8222-222222222222';
const txn1 = '33333333-3333-4333-8333-333333333333';

class _Connectivity implements Connectivity {
  _Connectivity(this.results);
  List<ConnectivityResult> results;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Records requests; answers with [respond] or fails like a dead network.
class _Adapter implements HttpClientAdapter {
  bool networkUp = true;
  final List<RequestOptions> requests = [];
  Map<String, dynamic> body = {'data': 'ok'};
  int status = 200;
  int Function(RequestOptions)? statusFor;
  dynamic Function(RequestOptions)? bodyFor;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path != '/v1/sync/metrics') requests.add(options); // reports are not part of what these tests check
    if (!networkUp) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    final s = statusFor?.call(options) ?? status;
    final b = bodyFor?.call(options) ?? body;
    return ResponseBody.fromString(jsonEncode(b), s, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('entity adapters', () {
    test('recognise writes to transactions, goals and loans', () {
      expect(matchWrite('POST', '/v1/transactions', {})!.op, 'create');
      expect(matchWrite('PUT', '/v1/transactions/$txn1', {})!.targetIds, [txn1]);
      expect(matchWrite('DELETE', '/v1/goals/$txn1', null)!.entity, 'goal');
      expect(matchWrite('PUT', '/v1/loans/$txn1', {})!.entity, 'loan');

      final bulk = matchWrite('POST', '/v1/transactions/bulk-delete', {'ids': [txn1, cat]})!;
      expect(bulk.op, 'delete');
      expect(bulk.targetIds, [txn1, cat]);
    });

    test('ignore everything else (reads, sub-resources, other entities)', () {
      expect(matchWrite('GET', '/v1/transactions', null), isNull);
      expect(matchWrite('POST', '/v1/goals/$txn1/contributions', {})!.entity, 'goal_contribution'); // a child, not a goal
      expect(matchWrite('POST', '/v1/receipt-scans', {}), isNull);
      expect(matchWrite('POST', '/v1/coach/messages', {}), isNull);
      expect(matchWrite('PUT', '/v1/transactions/not-a-uuid', {}), isNull);
    });

    test('a locally built transaction has the API shape, a Money amount and a pending flag', () async {
      final record = await const TransactionAdapter().buildRecord(
        {
          'id': txn1,
          'financial_account_id': acct,
          'category_id': cat,
          'type': 'expense',
          'amount': 12500.5,
          'occurred_at': '2026-10-06T10:00:00Z',
          'merchant': 'Shoprite',
        },
        (path, id) async => path == '/v1/accounts'
            ? {'id': id, 'name': 'Airtel Money', 'currency': 'MWK'}
            : {'id': id, 'name': 'Groceries', 'kind': 'expense'},
      );

      expect(record['amount']['formatted'], 'MK 12,500.50');
      expect(record['amount']['minor_units'], 1250050);
      expect(record['category']['name'], 'Groceries');
      expect(record['financial_account']['name'], 'Airtel Money');
      expect(record['_pending'], true);
      expect(record['source'], 'manual');
    });

    test('patching changes type and amount and keeps the currency', () {
      final base = {
        'id': txn1,
        'type': 'expense',
        'currency': 'MWK',
        'amount': {'minor_units': 100, 'currency': 'MWK', 'amount': 1.0, 'formatted': 'MK 1.00'},
      };
      final patched = const TransactionAdapter().applyPatch(base, {'type': 'income', 'amount': 2000});

      expect(patched['type'], 'income');
      expect(patched['amount']['formatted'], 'MK 2,000.00');
      expect(patched['_pending'], true);
      expect(base['type'], 'expense'); // the original is not mutated
    });

    test('a locally built goal and loan carry Money fields the app already parses', () async {
      final goal = await const GoalAdapter().buildRecord(
        {'id': txn1, 'name': 'Car', 'type': 'car', 'target': 500000}, (_, _) async => null);
      expect(goal['target']['formatted'], 'MK 500,000.00');
      expect(goal['current']['minor_units'], 0);

      final loan = await const LoanAdapter().buildRecord(
        {'id': txn1, 'name': 'Bank', 'principal': 100000, 'term_months': 12}, (_, _) async => null);
      expect(loan['principal']['formatted'], 'MK 100,000.00');
      expect(loan['progress']['outstanding']['formatted'], 'MK 100,000.00');
    });
  });

  group('overlay', () {
    late MemoryStore store;
    late OverlayEngine overlay;

    PendingMutation mut(String op, {String id = 'm1', List<String> targets = const [], Map<String, dynamic> body = const {}, Map<String, dynamic> effect = const {}}) =>
        PendingMutation(
          id: id, userId: 'u1', entity: 'transaction', op: op, targetIds: targets,
          method: 'POST', path: '/v1/transactions', body: body, effect: effect, createdMs: 1,
        );

    setUp(() {
      store = MemoryStore();
      overlay = OverlayEngine(mutations: store, cache: store);
    });

    final listJson = {
      'data': [
        {'id': txn1, 'type': 'expense', 'financial_account_id': acct, 'currency': 'MWK', 'merchant': 'Old'},
      ],
    };

    test('a queued create appears first, a queued edit shows, a queued delete disappears', () async {
      await store.enqueue(mut('create', id: 'a', targets: ['new-1'], effect: {'record': {'id': 'new-1', 'financial_account_id': acct, 'type': 'expense'}}));
      await store.enqueue(mut('update', id: 'b', targets: [txn1], body: {'merchant': 'Edited'}));

      final result = await overlay.apply(RequestOptions(path: '/v1/transactions'), 'u1', listJson) as Map;
      final data = result['data'] as List;

      expect(data.first['id'], 'new-1');
      expect(data.last['merchant'], 'Edited');
      expect(data.last['_pending'], true);

      await store.enqueue(mut('delete', id: 'c', targets: [txn1]));
      final after = await overlay.apply(RequestOptions(path: '/v1/transactions'), 'u1', listJson) as Map;
      expect((after['data'] as List).map((e) => e['id']), ['new-1']);
    });

    test('a queued create only shows in lists it belongs to', () async {
      await store.enqueue(mut('create', targets: ['new-1'], effect: {'record': {'id': 'new-1', 'financial_account_id': acct, 'type': 'expense'}}));

      final other = RequestOptions(path: '/v1/transactions', queryParameters: {'financial_account_id': 'someone-else'});
      final mine = RequestOptions(path: '/v1/transactions', queryParameters: {'financial_account_id': acct});
      final page2 = RequestOptions(path: '/v1/transactions', queryParameters: {'page': 2});

      expect(((await overlay.apply(other, 'u1', {'data': []}) as Map)['data'] as List), isEmpty);
      expect(((await overlay.apply(mine, 'u1', {'data': []}) as Map)['data'] as List), hasLength(1));
      expect(((await overlay.apply(page2, 'u1', {'data': []}) as Map)['data'] as List), isEmpty);
    });

    test('detail reads get queued edits, and a record created offline can be opened', () async {
      await store.enqueue(mut('create', id: 'a', targets: ['new-1'], effect: {'record': {'id': 'new-1', 'type': 'expense', 'currency': 'MWK', 'notes': 'x'}}));
      await store.enqueue(mut('update', id: 'b', targets: ['33333333-3333-4333-8333-333333333399'], body: {'notes': 'later'}));

      final id = '33333333-3333-4333-8333-333333333399';
      await store.enqueue(mut('create', id: 'c', targets: [id], effect: {'record': {'id': id, 'notes': 'first'}}));
      await store.enqueue(mut('update', id: 'd', targets: [id], body: {'notes': 'second'}));

      final built = await overlay.pendingDetail(RequestOptions(path: '/v1/transactions/$id'), 'u1');
      expect(built!['data']['notes'], 'second');

      final cached = await overlay.apply(
        RequestOptions(path: '/v1/transactions/$txn1'), 'u1', {'data': {'id': txn1, 'notes': 'server'}}) as Map;
      expect(cached['data']['notes'], 'server'); // nothing queued for txn1
    });

    test('other users\' queued changes never leak in', () async {
      await store.enqueue(mut('create', targets: ['new-1'], effect: {'record': {'id': 'new-1'}}));
      final result = await overlay.apply(RequestOptions(path: '/v1/transactions'), 'someone-else', {'data': []}) as Map;
      expect(result['data'], isEmpty);
    });

    test('versions are read from list and detail payloads', () {
      final v = OverlayEngine.versionsIn('/v1/transactions', {
        'data': [
          {'id': 'a', 'updated_at': '2026-10-06T10:00:00Z'},
          {'id': 'b'},
        ],
      });
      expect(v, {'a': '2026-10-06T10:00:00Z'});
      expect(OverlayEngine.versionsIn('/v1/goals/x', {'data': {'id': 'g', 'updated_at': 't'}}), {'g': 't'});
    });
  });

  group('write interceptor', () {
    late MemoryStore store;
    late _Adapter adapter;
    late _Connectivity connectivity;
    late Dio dio;
    var active = true;
    var queued = 0;

    setUp(() {
      store = MemoryStore();
      adapter = _Adapter();
      connectivity = _Connectivity([ConnectivityResult.wifi]);
      active = true;
      queued = 0;
      final overlay = OverlayEngine(mutations: store, cache: store);
      dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter
        ..interceptors.add(OfflineWriteInterceptor(
          store: store,
          cache: store,
          overlay: overlay,
          isActive: () => active,
          currentUserId: () => 'u1',
          onQueued: () => queued++,
          connectivity: connectivity,
        ));
    });

    Map<String, dynamic> newTxn() => {
          'financial_account_id': acct,
          'type': 'expense',
          'amount': 500,
          'occurred_at': '2026-10-06T10:00:00Z',
        };

    test('online: sent normally, with an idempotency key and a client-chosen id', () async {
      await dio.post('/v1/transactions', data: newTxn());

      final sent = adapter.requests.single;
      expect(sent.headers['Idempotency-Key'], isNotNull);
      expect((sent.data as Map)['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(store.queue, isEmpty);
    });

    test('offline: queued, answered locally, and the record gets its own id', () async {
      connectivity.results = [ConnectivityResult.none];

      final res = await dio.post('/v1/transactions', data: newTxn());

      expect(adapter.requests, isEmpty); // never touched the network
      expect(res.statusCode, 201);
      expect(res.data['data']['_pending'], true);
      expect(res.data['data']['amount']['formatted'], 'MK 500.00');

      final m = store.queue.single;
      expect(m.op, 'create');
      expect(m.targetIds.single, res.data['data']['id']);
      expect(m.id, isNotEmpty); // the idempotency key
      expect(queued, 1);
    });

    test('online but the request fails for lack of a network: queued, not lost', () async {
      adapter.networkUp = false;

      final res = await dio.post('/v1/transactions', data: newTxn());

      expect(res.extra['queued'], true);
      expect(store.queue, hasLength(1));
    });

    test('a server rejection (validation) is surfaced, never queued', () async {
      adapter.status = 422;
      adapter.body = {'message': 'invalid'};

      await expectLater(dio.post('/v1/transactions', data: newTxn()), throwsA(isA<DioException>()));
      expect(store.queue, isEmpty);
    });

    test('new changes queue behind earlier ones so order is kept, even when online', () async {
      connectivity.results = [ConnectivityResult.none];
      final first = await dio.post('/v1/transactions', data: newTxn());

      connectivity.results = [ConnectivityResult.wifi]; // back online, but the queue is not empty
      await dio.put('/v1/transactions/${first.data['data']['id']}', data: {'notes': 'tweaked'});

      expect(adapter.requests, isEmpty);
      expect(store.queue.map((m) => m.op), ['create', 'update']);
    });

    test('an edit records the version it was based on, for the server-wins check', () async {
      await store.putVersions('u1', 'transaction', {txn1: '2026-10-06T08:00:00Z'});
      connectivity.results = [ConnectivityResult.none];

      await dio.put('/v1/transactions/$txn1', data: {'notes': 'x'});

      expect(store.queue.single.baseUpdatedAt, '2026-10-06T08:00:00Z');
    });

    test('bulk delete is queued as one deletion of every id', () async {
      connectivity.results = [ConnectivityResult.none];
      final res = await dio.post('/v1/transactions/bulk-delete', data: {'ids': [txn1, cat]});

      expect(res.statusCode, 204);
      expect(store.queue.single.targetIds, [txn1, cat]);
    });

    test('nothing changes while offline mode is off, and other endpoints are untouched', () async {
      active = false;
      await dio.post('/v1/transactions', data: newTxn());
      expect(adapter.requests.single.headers['Idempotency-Key'], isNull);

      active = true;
      connectivity.results = [ConnectivityResult.none];
      adapter.requests.clear();
      adapter.networkUp = false;
      await expectLater(dio.post('/v1/receipt-scans', data: {'name': 'x'}), throwsA(isA<DioException>()));
      expect(store.queue, isEmpty);
    });
  });

  group('sync', () {
    late MemoryStore store;
    late _Adapter adapter;
    late MutationSync sync;

    PendingMutation mutation(String id, String op, {String entity = 'transaction', String? base, List<String> targets = const [txn1], Map<String, dynamic> body = const {}}) =>
        PendingMutation(
          id: id, userId: 'u1', entity: entity, op: op, targetIds: targets,
          method: op == 'create' ? 'POST' : (op == 'update' ? 'PUT' : 'DELETE'),
          path: op == 'create' ? '/v1/${entity}s' : '/v1/${entity}s/${targets.first}',
          body: body, baseUpdatedAt: base, createdMs: 1,
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = MemoryStore();
      adapter = _Adapter();
      sync = MutationSync(
        store: store,
        tokenReader: () async => 'token',
        dioFactory: (token) => Dio(BaseOptions(baseUrl: 'https://api.test', validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
      );
    });

    test('replays in order with the idempotency key and the base version', () async {
      await store.enqueue(mutation('k1', 'create', body: {'id': txn1}));
      await store.enqueue(mutation('k2', 'update', base: '2026-10-06T08:00:00Z', body: {'notes': 'x'}));

      final result = await sync.flush();

      expect(result.applied, 2);
      expect(store.queue, isEmpty);
      expect(adapter.requests.map((r) => r.method), ['POST', 'PUT']);
      expect(adapter.requests[0].headers['Idempotency-Key'], 'k1');
      expect(adapter.requests[1].headers['X-Base-Updated-At'], '2026-10-06T08:00:00Z');
    });

    test('server wins: a conflict drops the change and tells the user', () async {
      await store.enqueue(mutation('k1', 'update', base: 'old', body: {'notes': 'mine'}));
      adapter.status = 409;
      adapter.body = {'code': 'conflict', 'message': 'changed elsewhere', 'data': {}};

      final result = await sync.flush();

      expect(result.conflicts, 1);
      expect(store.queue, isEmpty);
      final notices = await SyncNotices.load();
      expect(notices.single.kind, 'conflict');
      expect(notices.single.message, contains('changed elsewhere'));
    });

    test('deleting something already gone counts as done, editing it is reported', () async {
      await store.enqueue(mutation('k1', 'delete'));
      await store.enqueue(mutation('k2', 'update', body: {'notes': 'x'}));
      adapter.status = 404;

      final result = await sync.flush();

      expect(result.applied, 1); // the delete
      expect(result.dropped, 1); // the edit
      expect((await SyncNotices.load()).single.kind, 'missing');
    });

    test('an id that is already taken means an earlier attempt already created it', () async {
      await store.enqueue(mutation('k1', 'create', body: {'id': txn1}));
      adapter.status = 422;
      adapter.body = {'message': 'invalid', 'errors': {'id': ['taken']}};

      final result = await sync.flush();

      expect(result.applied, 1);
      expect(await SyncNotices.load(), isEmpty);
    });

    test('a validation rejection is dropped with the reason', () async {
      await store.enqueue(mutation('k1', 'create', body: {'id': txn1}));
      adapter.status = 422;
      adapter.body = {'message': 'invalid', 'errors': {'amount': ['The amount must be greater than 0.']}};

      final result = await sync.flush();

      expect(result.dropped, 1);
      expect((await SyncNotices.load()).single.message, contains('amount must be greater than 0'));
    });

    test('a server error stops the run and keeps order: later changes never overtake it', () async {
      await store.enqueue(mutation('k1', 'update', body: {'notes': 'a'}));
      await store.enqueue(mutation('k2', 'update', body: {'notes': 'b'}));
      adapter.status = 503;

      final result = await sync.flush();

      expect(adapter.requests, hasLength(1)); // k2 was not even tried
      expect(result.remaining, 2);
      expect(store.queue.first.attempts, 1);
      expect(store.queue.first.nextRetryMs, greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('a change backing off holds back the ones after it', () async {
      await store.enqueue(mutation('k1', 'update', body: {'notes': 'a'}));
      await store.enqueue(mutation('k2', 'update', body: {'notes': 'b'}));
      await store.reschedule('k1', attempts: 1, nextRetryMs: DateTime.now().millisecondsSinceEpoch + 60000);

      final result = await sync.flush();

      expect(adapter.requests, isEmpty);
      expect(result.remaining, 2);
    });

    test('no connection: nothing lost, retried later', () async {
      await store.enqueue(mutation('k1', 'create', body: {'id': txn1}));
      adapter.networkUp = false;

      final result = await sync.flush();

      expect(result.offline, true);
      expect(store.queue, hasLength(1));
    });

    test('signed out: the queue is left untouched', () async {
      await store.enqueue(mutation('k1', 'create', body: {'id': txn1}));
      final signedOut = MutationSync(store: store, tokenReader: () async => null);

      final result = await signedOut.flush();

      expect(result.remaining, 1);
      expect(adapter.requests, isEmpty);
    });

    test('an expired token (401) stops the run without dropping anything', () async {
      await store.enqueue(mutation('k1', 'create', body: {'id': txn1}));
      adapter.status = 401;

      final result = await sync.flush();

      expect(result.remaining, 1);
      expect(result.dropped, 0);
    });
  });

  test('cache interceptor layers queued changes on a live read too', () async {
    final store = MemoryStore();
    final adapter = _Adapter()
      ..bodyFor = (_) => {'data': <dynamic>[]};
    final connectivity = _Connectivity([ConnectivityResult.wifi]);
    final overlay = OverlayEngine(mutations: store, cache: store);
    await store.enqueue(PendingMutation(
      id: 'm1', userId: 'u1', entity: 'transaction', op: 'create', targetIds: const ['n1'],
      method: 'POST', path: '/v1/transactions', body: const {},
      effect: {'record': {'id': 'n1', 'type': 'expense'}}, createdMs: 1,
    ));

    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(OfflineCacheInterceptor(
        store: store,
        overlay: overlay,
        versions: store,
        isActive: () => true,
        currentUserId: () => 'u1',
        onServedFromCache: (_) {},
        onLiveResponse: () {},
        connectivity: connectivity,
      ));

    final res = await dio.get('/v1/transactions');
    await Future<void>.delayed(Duration.zero);

    expect((res.data['data'] as List).single['id'], 'n1'); // the queued create is visible
    // ...but only the real server response is what gets saved for later.
    expect((store.rows['u1|GET /v1/transactions']!.body as Map)['data'], isEmpty);
  });
}
