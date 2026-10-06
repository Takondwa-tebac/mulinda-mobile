import 'package:dio/dio.dart';

import 'cache_store.dart';
import 'entity_adapters.dart';
import 'mutation_store.dart';

/// Makes queued (not yet synced) changes visible on screen.
///
/// Reads come from the server or the saved cache, neither of which knows about
/// changes still waiting in the queue. This layers those changes on top of the
/// response: a queued create appears in the list, an edit shows its new values,
/// a delete disappears. Records touched this way carry `_pending: true` so the
/// UI can mark them "waiting to sync".
class OverlayEngine {
  OverlayEngine({required this.mutations, required this.cache});

  final MutationStore mutations;
  final CacheStore cache;

  /// Looks up a record (e.g. a category's name) in the saved reads.
  RecordLookup lookupFor(String userId) => (collectionPath, id) async {
        final pages = await cache.getByPrefix(userId, 'GET $collectionPath');
        for (final page in pages) {
          final data = page.body is Map ? (page.body as Map)['data'] : page.body;
          if (data is List) {
            for (final item in data) {
              if (item is Map && item['id']?.toString() == id) return item.cast<String, dynamic>();
            }
          }
        }
        return null;
      };

  /// [json] with this user's queued changes applied, or [json] untouched when
  /// the request is not for an offline-capable record or nothing is queued.
  Future<dynamic> apply(RequestOptions options, String userId, dynamic json) async {
    for (final adapter in kEntityAdapters) {
      final isList = adapter.isList(options.path);
      final detail = isList ? null : adapter.detailId(options.path);
      if (!isList && detail == null) continue;

      final queued = (await mutations.all(userId)).where((m) => m.entity == adapter.entity).toList();
      if (queued.isEmpty || json is! Map || json['data'] == null) return json;

      if (isList && json['data'] is List) {
        final data = List<dynamic>.from(json['data'] as List);
        for (final m in queued) {
          _applyToList(adapter, m, data, options.queryParameters);
        }
        return {...json, 'data': data};
      }

      if (detail != null && json['data'] is Map) {
        var record = (json['data'] as Map).cast<String, dynamic>();
        for (final m in queued) {
          if (m.op == 'update' && m.targetIds.contains(detail)) record = adapter.applyPatch(record, m.body);
        }
        return {...json, 'data': record};
      }
      return json;
    }
    return json;
  }

  void _applyToList(EntityAdapter adapter, PendingMutation m, List<dynamic> data, Map<String, dynamic> query) {
    switch (m.op) {
      case 'create':
        final record = m.effect['record'];
        if (record is! Map) return;
        final map = record.cast<String, dynamic>();
        final exists = data.any((e) => e is Map && e['id']?.toString() == map['id']?.toString());
        if (!exists && adapter.matchesQuery(map, query)) data.insert(0, map);
      case 'update':
        for (var i = 0; i < data.length; i++) {
          final item = data[i];
          if (item is Map && m.targetIds.contains(item['id']?.toString())) {
            data[i] = adapter.applyPatch(item.cast<String, dynamic>(), m.body);
          }
        }
      case 'delete':
        data.removeWhere((e) => e is Map && m.targetIds.contains(e['id']?.toString()));
    }
  }

  /// A detail response for a record that exists only locally (created offline,
  /// never fetched), built from its queued create plus later edits. Null when
  /// [options] is not such a request.
  Future<Map<String, dynamic>?> pendingDetail(RequestOptions options, String userId) async {
    for (final adapter in kEntityAdapters) {
      final id = adapter.detailId(options.path);
      if (id == null) continue;
      Map<String, dynamic>? record;
      for (final m in (await mutations.all(userId)).where((m) => m.entity == adapter.entity)) {
        if (m.op == 'create' && m.targetIds.contains(id) && m.effect['record'] is Map) {
          record = (m.effect['record'] as Map).cast<String, dynamic>();
        } else if (record != null && m.op == 'update' && m.targetIds.contains(id)) {
          record = adapter.applyPatch(record, m.body);
        } else if (m.op == 'delete' && m.targetIds.contains(id)) {
          return null;
        }
      }
      return record == null ? null : {'data': record};
    }
    return null;
  }

  /// A detail response built from the saved list pages, for a record whose own
  /// detail page was never opened (so was never saved). Queued edits are applied.
  /// Null when the record is not in any saved list.
  Future<Map<String, dynamic>?> detailFromSavedLists(RequestOptions options, String userId) async {
    for (final adapter in kEntityAdapters) {
      final id = adapter.detailId(options.path);
      if (id == null) continue;

      Map<String, dynamic>? record;
      for (final page in await cache.getByPrefix(userId, 'GET ${adapter.collection}')) {
        final data = page.body is Map ? (page.body as Map)['data'] : null;
        if (data is List) {
          for (final item in data) {
            if (item is Map && item['id']?.toString() == id) record = item.cast<String, dynamic>();
          }
        }
        if (record != null) break;
      }
      if (record == null) return null;

      var current = record;
      for (final m in (await mutations.all(userId)).where((m) => m.entity == adapter.entity)) {
        if (m.op == 'update' && m.targetIds.contains(id)) current = adapter.applyPatch(current, m.body);
        if (m.op == 'delete' && m.targetIds.contains(id)) return null;
      }
      return {'data': current};
    }
    return null;
  }

  /// `id → updated_at` for every record in a successful read, so a later queued
  /// edit can tell the server which version it was based on.
  static Map<String, String> versionsIn(String path, dynamic json) {
    if (json is! Map) return const {};
    final data = json['data'];
    final out = <String, String>{};
    void take(dynamic item) {
      if (item is Map && item['id'] != null && item['updated_at'] != null) {
        out[item['id'].toString()] = item['updated_at'].toString();
      }
    }

    if (data is List) {
      data.forEach(take);
    } else {
      take(data);
    }
    return out;
  }
}
