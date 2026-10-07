import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/offline/mutation_store.dart';
import 'package:mulinda_mobile/core/offline/mutation_sync.dart';
import 'package:mulinda_mobile/core/offline/offline_prefetch.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_store.dart';

/// A fake server: a batch endpoint (accepts, then reports the results), the
/// single-request endpoints and the metrics endpoint.
class _Server implements HttpClientAdapter {
  final requests = <String>[];
  final bodies = <String, dynamic>{};
  int batchStatus = 202;
  String batchState = 'completed';
  int itemStatus = 201;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    requests.add('${o.method} ${o.path}');
    bodies['${o.method} ${o.path}'] = o.data;

    Map<String, dynamic> json;
    var status = 200;
    if (o.method == 'POST' && o.path == '/v1/sync/batches') {
      status = batchStatus;
      json = {
        'data': {'id': 'batch-1', 'status': 'queued'},
      };
    } else if (o.path == '/v1/sync/batches/batch-1') {
      final items = (bodies['POST /v1/sync/batches'] as Map)['items'] as List;
      json = {
        'data': {
          'id': 'batch-1',
          'status': batchState,
          if (batchState == 'completed')
            'results': [
              for (final i in items) {'id': i['id'], 'status': itemStatus},
            ],
        },
      };
    } else if (o.path == '/v1/sync/metrics') {
      status = 202;
      json = {};
    } else {
      status = 201;
      json = {'data': {}};
    }
    return ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MemoryStore store;
  late _Server server;
  late MutationSync sync;

  PendingMutation goal(String id) => PendingMutation(
    id: id,
    userId: 'u1',
    entity: 'goal',
    op: 'create',
    targetIds: [id],
    method: 'POST',
    path: '/v1/goals',
    body: {'id': id, 'name': 'Goal $id'},
    createdMs: 1,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({'offline_mode_enabled_u1': true});
    MutationSync.batchPollDelays = const [Duration.zero, Duration.zero];
    store = MemoryStore();
    server = _Server();
    sync = MutationSync(
      store: store,
      tokenReader: () async => 'token',
      dioFactory: (_) => Dio(
        BaseOptions(baseUrl: 'https://api.test', validateStatus: (_) => true),
      )..httpClientAdapter = server,
    );
  });

  group('batch sync', () {
    test(
      'three or more waiting changes go to the server as one batch',
      () async {
        for (final id in ['a', 'b', 'c']) {
          await store.enqueue(goal(id));
        }

        final result = await sync.flush();

        expect(result.applied, 3);
        expect(store.queue, isEmpty);
        expect(server.requests.where((r) => r == 'POST /v1/goals'), isEmpty);
        final sent =
            (server.bodies['POST /v1/sync/batches'] as Map)['items'] as List;
        expect(sent.map((i) => i['id']), ['a', 'b', 'c']);
      },
    );

    test('fewer than three are replayed one by one', () async {
      await store.enqueue(goal('a'));
      await store.enqueue(goal('b'));

      final result = await sync.flush();

      expect(result.applied, 2);
      expect(server.requests.where((r) => r == 'POST /v1/goals'), hasLength(2));
      expect(server.requests, isNot(contains('POST /v1/sync/batches')));
    });

    test(
      'falls back to one by one when the server cannot take a batch',
      () async {
        server.batchStatus = 404; // older server
        for (final id in ['a', 'b', 'c']) {
          await store.enqueue(goal(id));
        }

        final result = await sync.flush();

        expect(result.applied, 3);
        expect(
          server.requests.where((r) => r == 'POST /v1/goals'),
          hasLength(3),
        );
      },
    );

    test('falls back when the batch fails or is still running', () async {
      for (final state in ['failed', 'processing']) {
        server = _Server()..batchState = state;
        sync = MutationSync(
          store: store,
          tokenReader: () async => 'token',
          dioFactory: (_) => Dio(
            BaseOptions(
              baseUrl: 'https://api.test',
              validateStatus: (_) => true,
            ),
          )..httpClientAdapter = server,
        );
        for (final id in ['a', 'b', 'c']) {
          await store.enqueue(goal(id));
        }

        final result = await sync.flush();

        expect(result.applied, 3, reason: state);
        expect(
          server.requests.where((r) => r == 'POST /v1/goals'),
          hasLength(3),
          reason: state,
        );
      }
    });

    test(
      'a rejected change in the batch is dropped with a notice, the rest still apply',
      () async {
        server.itemStatus = 422;
        for (final id in ['a', 'b', 'c']) {
          await store.enqueue(goal(id));
        }

        final result = await sync.flush();

        expect(result.dropped, 3);
        expect(store.queue, isEmpty);
      },
    );
  });

  group('sync reports', () {
    test('a sync that did something reports counts only', () async {
      for (final id in ['a', 'b', 'c']) {
        await store.enqueue(goal(id));
      }

      await sync.flush();

      final report = server.bodies['POST /v1/sync/metrics'] as Map;
      expect(report['applied'], 3);
      expect(report['offline_mode_enabled'], true);
      expect(report.keys, isNot(contains('items')));
    });
  });

  group('incremental refresh plan', () {
    final all = [
      PrefetchStep('Goals', () async {}, dependsOn: {'goals'}),
      PrefetchStep('Loans', () async {}, dependsOn: {'loans'}),
      PrefetchStep('Categories', () async {}, dependsOn: {}),
      PrefetchStep('Notifications', () async {}),
    ];

    test(
      'first run (no position yet) refreshes everything and takes the server clock',
      () async {
        final plan = await OfflinePrefetcher.plan(
          all: all,
          cursor: null,
          force: false,
          fetchSummary: (_) async => {'server_time': 't1', 'changed': {}},
        );

        expect(plan.steps, hasLength(4));
        expect(plan.nextCursor, 't1');
      },
    );

    test(
      'later runs only refresh what changed, plus what the feed does not cover',
      () async {
        final plan = await OfflinePrefetcher.plan(
          all: all,
          cursor: 't1',
          force: false,
          fetchSummary: (_) async => {
            'server_time': 't2',
            'full_refresh_required': false,
            'changed': {'goals': true, 'loans': false},
          },
        );

        expect(plan.steps.map((s) => s.label), ['Goals', 'Notifications']);
        expect(plan.nextCursor, 't2');
      },
    );

    test(
      'too long away, forced or no answer from the server: refresh everything',
      () async {
        final tooOld = await OfflinePrefetcher.plan(
          all: all,
          cursor: 't1',
          force: false,
          fetchSummary: (_) async => {
            'server_time': 't2',
            'full_refresh_required': true,
            'changed': {},
          },
        );
        final forced = await OfflinePrefetcher.plan(
          all: all,
          cursor: 't1',
          force: true,
          fetchSummary: (_) async => {'server_time': 't3'},
        );
        final noAnswer = await OfflinePrefetcher.plan(
          all: all,
          cursor: 't1',
          force: false,
          fetchSummary: (_) async => null,
        );

        expect(tooOld.steps, hasLength(4));
        expect(forced.steps, hasLength(4));
        expect(noAnswer.steps, hasLength(4));
        expect(noAnswer.nextCursor, isNull);
      },
    );
  });
}
