import 'package:mulinda_mobile/core/offline/cache_store.dart';
import 'package:mulinda_mobile/core/offline/mutation_store.dart';
import 'package:mulinda_mobile/core/offline/offline_storage.dart';

/// In-memory stand-in for the encrypted store (cache + mutation queue + versions).
class MemoryStore implements CacheStore, MutationStore {
  final Map<String, CachedResponse> rows = {};
  final List<PendingMutation> queue = [];
  final Map<String, String> versions = {};
  int _seq = 0;

  // ---- CacheStore
  @override
  Future<void> put(String userId, String key, dynamic body) async {
    rows['$userId|$key'] = CachedResponse(body: body, fetchedAt: DateTime(2026, 10, 6, 14, 30));
  }

  @override
  Future<CachedResponse?> get(String userId, String key) async => rows['$userId|$key'];

  @override
  Future<List<CachedResponse>> getByPrefix(String userId, String keyPrefix) async =>
      rows.entries.where((e) => e.key.startsWith('$userId|$keyPrefix')).map((e) => e.value).toList();

  @override
  Future<List<CachedEntryUsage>> usage(String userId) async => [
        for (final e in rows.entries.where((e) => e.key.startsWith('$userId|')))
          CachedEntryUsage(e.key.substring(userId.length + 1), e.value.body.toString().length),
      ];

  @override
  Future<void> clearSaved(String userId) async {
    rows.removeWhere((k, _) => k.startsWith('$userId|'));
    versions.removeWhere((k, _) => k.startsWith('$userId|'));
  }

  @override
  Future<void> clearUser(String userId) async {
    rows.removeWhere((k, _) => k.startsWith('$userId|'));
    queue.removeWhere((m) => m.userId == userId);
    versions.removeWhere((k, _) => k.startsWith('$userId|'));
  }

  @override
  Future<void> clearAll() async {
    rows.clear();
    queue.clear();
    versions.clear();
  }

  // ---- MutationStore
  @override
  Future<void> enqueue(PendingMutation m) async {
    if (queue.any((q) => q.id == m.id)) return;
    queue.add(PendingMutation(
      id: m.id,
      userId: m.userId,
      entity: m.entity,
      op: m.op,
      targetIds: m.targetIds,
      method: m.method,
      path: m.path,
      body: m.body,
      baseUpdatedAt: m.baseUpdatedAt,
      effect: m.effect,
      createdMs: m.createdMs,
      seq: ++_seq,
    ));
  }

  @override
  Future<List<PendingMutation>> all(String userId) async => queue.where((m) => m.userId == userId).toList();

  @override
  Future<List<PendingMutation>> allPending() async => List.of(queue);

  @override
  Future<int> count({String? userId}) async => userId == null ? queue.length : queue.where((m) => m.userId == userId).length;

  @override
  Future<void> remove(String id) async => queue.removeWhere((m) => m.id == id);

  @override
  Future<void> reschedule(String id, {required int attempts, required int nextRetryMs, String? error}) async {
    final i = queue.indexWhere((m) => m.id == id);
    if (i >= 0) queue[i] = queue[i].copyWith(attempts: attempts, nextRetryMs: nextRetryMs, lastError: error);
  }

  @override
  Future<void> clearMutations({String? userId}) async =>
      userId == null ? queue.clear() : queue.removeWhere((m) => m.userId == userId);

  @override
  Future<void> putVersions(String userId, String entity, Map<String, String> updatedAtById) async {
    for (final e in updatedAtById.entries) {
      versions['$userId|$entity|${e.key}'] = e.value;
    }
  }

  @override
  Future<String?> version(String userId, String entity, String id) async => versions['$userId|$entity|$id'];
}
