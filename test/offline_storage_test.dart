import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/offline/offline_storage.dart';

import 'support/memory_store.dart';

void main() {
  group('what is saved on the phone', () {
    test('groups saved responses by screen with item counts and sizes, biggest first', () {
      final b = StorageBreakdown.from(const [
        CachedEntryUsage('GET /v1/transactions?page=1', 5000),
        CachedEntryUsage('GET /v1/transactions?page=2', 3000),
        CachedEntryUsage('GET /v1/goals', 800),
        CachedEntryUsage('GET /v1/goals/abc', 200),
        CachedEntryUsage('GET /v1/something-new', 100),
      ]);

      expect(b.groups.map((g) => g.label), ['Transactions', 'Goals', 'Other']);
      expect(b.groups.first.items, 2);
      expect(b.groups.first.bytes, 8000);
      expect(b.totalBytes, 9100);
    });

    test('formats sizes for people', () {
      expect(StorageBreakdown.formatBytes(812), '812 B');
      expect(StorageBreakdown.formatBytes(2048), '2.0 KB');
      expect(StorageBreakdown.formatBytes(150 * 1024), '150 KB');
      expect(StorageBreakdown.formatBytes(3 * 1024 * 1024), '3.0 MB');
    });

    test('clearing saved data keeps the changes waiting to sync', () async {
      final store = MemoryStore();
      await store.put('u1', 'GET /v1/goals', {'data': []});
      await store.put('u2', 'GET /v1/goals', {'data': []});

      await store.clearSaved('u1');

      expect(await store.usage('u1'), isEmpty);
      expect(await store.usage('u2'), hasLength(1));
    });
  });
}
