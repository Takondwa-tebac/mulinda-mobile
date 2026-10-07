import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money_json.dart';
import 'package:mulinda_mobile/core/offline/entity_adapters.dart';
import 'package:mulinda_mobile/core/offline/mutation_store.dart';
import 'package:mulinda_mobile/core/offline/offline_write_interceptor.dart';
import 'package:mulinda_mobile/core/offline/overlay_engine.dart';

import 'support/memory_store.dart';

const acct1 = '88888888-8888-4888-8888-888888888888';
const tx1 = '99999999-9999-4999-8999-999999999999';

class _Offline implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _DeadNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> accountJson({int balance = 100000}) => {
      'id': acct1,
      'name': 'Airtel Money',
      'currency': 'MWK',
      'current_balance': moneyJson(balance / 100, 'MWK'),
      'updated_at': '2026-10-06T08:00:00Z',
    };

Map<String, dynamic> txJson(String type, int minor) => {
      'id': tx1,
      'type': type,
      'financial_account_id': acct1,
      'currency': 'MWK',
      'amount': moneyJson(minor / 100, 'MWK'),
    };

PendingMutation txMut(String id, String op, Map<String, int> deltas) => PendingMutation(
      id: id, userId: 'u1', entity: 'transaction', op: op, targetIds: const [tx1],
      method: 'POST', path: '/v1/transactions', body: const {},
      effect: {'balance_deltas': deltas}, createdMs: 1,
    );

void main() {
  late MemoryStore store;
  late OverlayEngine overlay;

  setUp(() {
    store = MemoryStore();
    overlay = OverlayEngine(mutations: store, cache: store);
  });

  Dio offlineDio() => Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = _DeadNetwork()
    ..interceptors.add(OfflineWriteInterceptor(
      store: store,
      cache: store,
      overlay: overlay,
      isActive: () => true,
      currentUserId: () => 'u1',
      onQueued: () {},
      connectivity: _Offline(),
    ));

  group('accounts offline', () {
    test('accounts are recognised, and an offline account starts at its opening balance', () async {
      expect(matchWrite('POST', '/v1/accounts', {})!.entity, 'account');
      expect(matchWrite('DELETE', '/v1/accounts/$acct1', null)!.op, 'delete');

      final record = await const AccountAdapter().buildRecord(
        {'id': acct1, 'name': 'Cash', 'type': 'cash', 'opening_balance': 2500}, (_, _) async => null);
      expect(record['current_balance']['formatted'], 'MK 2,500.00');
      expect(record['_pending'], true);
    });

    test('a created account is queued and shows straight away', () async {
      final res = await offlineDio().post('/v1/accounts', data: {'name': 'Cash', 'type': 'cash', 'opening_balance': 100});

      expect(res.statusCode, 201);
      expect(store.queue.single.entity, 'account');
      final list = await overlay.apply(RequestOptions(path: '/v1/accounts'), 'u1', {'data': []}) as Map;
      expect((list['data'] as List).single['name'], 'Cash');
    });
  });

  group('estimated balances', () {
    test('queued transactions move the balance and flag it as an estimate', () async {
      await store.enqueue(txMut('t1', 'create', {acct1: -25000})); // an expense of MK 250

      final list = await overlay.apply(RequestOptions(path: '/v1/accounts'), 'u1', {'data': [accountJson()]}) as Map;
      final account = (list['data'] as List).single as Map;

      expect(account['current_balance']['minor_units'], 75000);
      expect(account['balance_estimated'], true);
    });

    test('the balance is untouched when nothing queued affects it', () async {
      await store.enqueue(txMut('t1', 'create', {'some-other-account': -5000}));

      final account = ((await overlay.apply(RequestOptions(path: '/v1/accounts'), 'u1', {'data': [accountJson()]}) as Map)['data'] as List).single as Map;

      expect(account['current_balance']['minor_units'], 100000);
      expect(account.containsKey('balance_estimated'), false);
    });

    test('several queued changes add up, on the detail view as well', () async {
      await store.enqueue(txMut('t1', 'create', {acct1: -25000}));
      await store.enqueue(txMut('t2', 'create', {acct1: 100000})); // income of MK 1,000

      final detail = (await overlay.apply(RequestOptions(path: '/v1/accounts/$acct1'), 'u1', {'data': accountJson()}) as Map)['data'] as Map;

      expect(detail['current_balance']['minor_units'], 175000);
    });

    test('an account created offline shows the balance of transactions queued against it', () async {
      await store.enqueue(PendingMutation(
        id: 'a1', userId: 'u1', entity: 'account', op: 'create', targetIds: const [acct1],
        method: 'POST', path: '/v1/accounts', body: const {},
        effect: {'record': {'id': acct1, 'name': 'New', 'currency': 'MWK', 'current_balance': moneyJson(500, 'MWK')}}, createdMs: 1,
      ));
      await store.enqueue(txMut('t1', 'create', {acct1: -10000}));

      final list = await overlay.apply(RequestOptions(path: '/v1/accounts'), 'u1', {'data': []}) as Map;

      expect(((list['data'] as List).single as Map)['current_balance']['minor_units'], 40000);
    });

    test('how a transaction changes a balance is signed by its type', () {
      expect(signedAmountMinor('income', 5000), 5000);
      expect(signedAmountMinor('expense', 5000), -5000);
      expect(signedAmountMinor('transfer', 5000), 0);
    });
  });

  group('queuing records the balance effect', () {
    test('a new transaction records the balance change it will cause', () async {
      await offlineDio().post('/v1/transactions', data: {
        'financial_account_id': acct1, 'type': 'expense', 'amount': 250, 'occurred_at': '2026-10-06T10:00:00Z',
      });

      expect(store.queue.single.effect['balance_deltas'], {acct1: -25000});
    });

    test('editing a saved transaction records only the difference', () async {
      await store.put('u1', 'GET /v1/transactions', {'data': [txJson('expense', 25000)]});

      await offlineDio().put('/v1/transactions/$tx1', data: {'amount': 400}); // 250 -> 400 expense

      expect(store.queue.single.effect['balance_deltas'], {acct1: -15000});
    });

    test('changing a transaction from expense to income swings the balance both ways', () async {
      await store.put('u1', 'GET /v1/transactions', {'data': [txJson('expense', 25000)]});

      await offlineDio().put('/v1/transactions/$tx1', data: {'type': 'income'});

      expect(store.queue.single.effect['balance_deltas'], {acct1: 50000});
    });

    test('deleting transactions gives the money back to each account', () async {
      await store.put('u1', 'GET /v1/transactions', {'data': [txJson('expense', 25000)]});

      await offlineDio().post('/v1/transactions/bulk-delete', data: {'ids': [tx1]});

      expect(store.queue.single.effect['balance_deltas'], {acct1: 25000});
    });

    test('a second offline edit builds on the first, not on the saved copy', () async {
      await store.put('u1', 'GET /v1/transactions', {'data': [txJson('expense', 25000)]});
      final dio = offlineDio();

      await dio.put('/v1/transactions/$tx1', data: {'amount': 400}); // expense 250 -> 400
      await dio.put('/v1/transactions/$tx1', data: {'amount': 500}); // 400 -> 500

      expect(store.queue.map((m) => m.effect['balance_deltas']), [
        {acct1: -15000},
        {acct1: -10000},
      ]);
    });
  });

  test('the queue has a limit, and reaching it asks the user to sync first', () async {
    for (var i = 0; i < kMaxQueuedChanges; i++) {
      await store.enqueue(PendingMutation(
        id: 'm$i', userId: 'u1', entity: 'transaction', op: 'create', targetIds: const [],
        method: 'POST', path: '/v1/transactions', body: const {}, createdMs: i,
      ));
    }

    await expectLater(
      offlineDio().post('/v1/transactions', data: {'financial_account_id': acct1, 'type': 'expense', 'amount': 1, 'occurred_at': 'x'}),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 429)),
    );
    expect(store.queue, hasLength(kMaxQueuedChanges)); // nothing was added
  });
}
