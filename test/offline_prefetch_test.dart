import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/offline/mutation_store.dart';
import 'package:mulinda_mobile/core/offline/offline_prefetch.dart';
import 'package:mulinda_mobile/core/offline/overlay_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_store.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('saving data for offline use', () {
    test('runs every step in order, reports progress and remembers when it finished', () async {
      final ran = <String>[];
      final progress = <String>[];

      final result = await OfflinePrefetcher.run(
        steps: [
          PrefetchStep('Dashboard', () async => ran.add('dashboard')),
          PrefetchStep('Accounts', () async => ran.add('accounts')),
        ],
        isOnline: () async => true,
        prefs: prefs,
        onProgress: (done, total, label) => progress.add('$done/$total $label'),
      );

      expect(ran, ['dashboard', 'accounts']);
      expect(result.saved, 2);
      expect(result.failed, 0);
      expect(progress.first, '0/2 Dashboard');
      expect(progress.last, startsWith('2/2'));
      expect(OfflinePrefetcher.lastSaved(prefs), isNotNull);
    });

    test('one screen failing never stops the others', () async {
      final ran = <String>[];

      final result = await OfflinePrefetcher.run(
        steps: [
          PrefetchStep('A', () async => ran.add('a')),
          PrefetchStep('B', () async => throw DioException(requestOptions: RequestOptions(path: '/x'))),
          PrefetchStep('C', () async => ran.add('c')),
        ],
        isOnline: () async => true,
        prefs: prefs,
      );

      expect(ran, ['a', 'c']);
      expect(result.saved, 2);
      expect(result.failed, 1);
      expect(OfflinePrefetcher.lastSaved(prefs), isNotNull);
    });

    test('with no connection nothing is attempted and nothing is recorded as saved', () async {
      var ran = false;

      final result = await OfflinePrefetcher.run(
        steps: [PrefetchStep('A', () async => ran = true)],
        isOnline: () async => false,
        prefs: prefs,
      );

      expect(result.offline, true);
      expect(ran, false);
      expect(OfflinePrefetcher.lastSaved(prefs), isNull);
    });

    test('if the connection drops part way it stops instead of failing every step', () async {
      var online = true;
      final ran = <String>[];

      final result = await OfflinePrefetcher.run(
        steps: [
          PrefetchStep('A', () async => ran.add('a')),
          PrefetchStep('B', () async {
            online = false;
            throw DioException(requestOptions: RequestOptions(path: '/x'));
          }),
          PrefetchStep('C', () async => ran.add('c')),
          PrefetchStep('D', () async => ran.add('d')),
        ],
        isOnline: () async => online,
        prefs: prefs,
      );

      expect(ran, ['a']);
      expect(result.offline, true);
      expect(result.saved, 1);
      expect(result.failed, 3); // B plus the two it never reached
    });

    test('saved data counts as stale after a couple of hours', () async {
      expect(OfflinePrefetcher.isStale(prefs), true); // never saved

      await prefs.setInt(OfflinePrefetcher.lastKey, DateTime.now().millisecondsSinceEpoch);
      expect(OfflinePrefetcher.isStale(prefs), false);
      expect(OfflinePrefetcher.isStale(prefs, now: DateTime.now().add(const Duration(hours: 3))), true);
    });
  });

  group('opening a record that only appears in a saved list', () {
    const id = '33333333-3333-4333-8333-333333333333';
    late MemoryStore store;
    late OverlayEngine overlay;

    setUp(() {
      store = MemoryStore();
      overlay = OverlayEngine(mutations: store, cache: store);
    });

    test('is built from the saved list, so a detail screen opens offline', () async {
      await store.put('u1', 'GET /v1/transactions?per_page=50', {
        'data': [
          {'id': id, 'notes': 'from the list', 'currency': 'MWK'},
        ],
      });

      final detail = await overlay.detailFromSavedLists(RequestOptions(path: '/v1/transactions/$id'), 'u1');

      expect(detail!['data']['notes'], 'from the list');
    });

    test('shows queued edits, and nothing when it was deleted offline', () async {
      await store.put('u1', 'GET /v1/transactions', {
        'data': [
          {'id': id, 'notes': 'before', 'currency': 'MWK'},
        ],
      });
      await store.enqueue(PendingMutation(
        id: 'm1', userId: 'u1', entity: 'transaction', op: 'update', targetIds: const [id],
        method: 'PUT', path: '/v1/transactions/$id', body: const {'notes': 'after'}, createdMs: 1,
      ));

      final edited = await overlay.detailFromSavedLists(RequestOptions(path: '/v1/transactions/$id'), 'u1');
      expect(edited!['data']['notes'], 'after');

      await store.enqueue(PendingMutation(
        id: 'm2', userId: 'u1', entity: 'transaction', op: 'delete', targetIds: const [id],
        method: 'DELETE', path: '/v1/transactions/$id', body: const {}, createdMs: 2,
      ));
      expect(await overlay.detailFromSavedLists(RequestOptions(path: '/v1/transactions/$id'), 'u1'), isNull);
    });

    test('is null when the record is in no saved list or belongs to another user', () async {
      await store.put('someone-else', 'GET /v1/transactions', {
        'data': [
          {'id': id, 'notes': 'theirs'},
        ],
      });

      expect(await overlay.detailFromSavedLists(RequestOptions(path: '/v1/transactions/$id'), 'u1'), isNull);
    });
  });
}
