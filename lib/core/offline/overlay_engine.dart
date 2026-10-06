import 'package:dio/dio.dart';

import 'cache_store.dart';
import 'entity_adapters.dart';
import 'mutation_store.dart';

/// Makes queued (not yet synced) changes visible on screen.
///
/// Reads come from the server or the saved cache, neither of which knows about
/// changes still waiting in the queue. This layers those changes on top of the
/// response: a queued create appears in the list, an edit shows its new values,
/// a delete disappears, and a contribution or repayment shows in its goal or
/// loan and moves the saved or outstanding total. Records touched this way carry
/// `_pending: true` so the UI can mark them "waiting to sync".
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
          if (data is Map && data['id']?.toString() == id) return data.cast<String, dynamic>();
        }
        return null;
      };

  /// A saved contribution/repayment (they live inside the parent's detail), or a
  /// queued create of one, so a queued edit knows how much it changes by.
  Future<Map<String, dynamic>?> findChild(String userId, ChildAdapter adapter, String parentId, String childId) async {
    final detail = await cache.get(userId, 'GET ${adapter.parentCollection}/$parentId');
    final data = detail?.body is Map ? (detail!.body as Map)['data'] : null;
    final list = data is Map ? data[adapter.childKey] : null;
    if (list is List) {
      for (final item in list) {
        if (item is Map && item['id']?.toString() == childId) return item.cast<String, dynamic>();
      }
    }
    for (final m in await mutations.all(userId)) {
      if (m.entity == adapter.entity && m.op == 'create' && m.targetIds.contains(childId) && m.effect['record'] is Map) {
        return (m.effect['record'] as Map).cast<String, dynamic>();
      }
    }
    return null;
  }

  /// A record as it stands now: the saved copy (or a queued create) with queued
  /// edits applied, or null if it is unknown or queued for deletion. Used to work
  /// out how an edit or delete changes an account's balance.
  Future<Map<String, dynamic>?> effectiveRecord(String userId, EntityAdapter adapter, String id) async {
    final all = (await mutations.all(userId)).where((m) => m.entity == adapter.entity).toList();
    Map<String, dynamic>? record = await lookupFor(userId)(adapter.collection, id);
    for (final m in all) {
      if (m.op == 'create' && m.targetIds.contains(id) && m.effect['record'] is Map) {
        record = (m.effect['record'] as Map).cast<String, dynamic>();
      } else if (record != null && m.op == 'update' && m.targetIds.contains(id)) {
        record = adapter.applyPatch(record, m.body);
      } else if (m.op == 'delete' && m.targetIds.contains(id)) {
        return null;
      }
    }
    return record;
  }

  /// Move an account's balance by the transactions waiting to sync.
  Map<String, dynamic> _withBalance(EntityAdapter adapter, Map<String, dynamic> record, List<PendingMutation> all) {
    if (adapter is! AccountAdapter) return record;
    final id = record['id']?.toString();
    var delta = 0;
    for (final m in all) {
      if (m.entity != 'transaction') continue;
      final deltas = m.effect['balance_deltas'];
      if (deltas is Map && deltas[id] is num) delta += (deltas[id] as num).toInt();
    }
    return adapter.adjustBalance(record, delta);
  }

  /// [json] with this user's queued changes applied, or [json] untouched when
  /// the request is not for an offline-capable record or nothing is queued.
  Future<dynamic> apply(RequestOptions options, String userId, dynamic json) async {
    for (final adapter in kEntityAdapters) {
      final isList = adapter.isList(options.path);
      final detail = isList ? null : adapter.detailId(options.path);
      if (!isList && detail == null) continue;

      final all = await mutations.all(userId);
      final own = all.where((m) => m.entity == adapter.entity).toList();
      final childEntity = adapter.childAdapter?.entity;
      final children = childEntity == null ? <PendingMutation>[] : all.where((m) => m.entity == childEntity).toList();
      final touchesBalance = adapter is AccountAdapter && all.any((m) => m.entity == 'transaction' && m.effect['balance_deltas'] != null);
      if ((own.isEmpty && children.isEmpty && !touchesBalance) || json is! Map || json['data'] == null) return json;

      if (isList && json['data'] is List) {
        final data = List<dynamic>.from(json['data'] as List);
        for (final m in own) {
          _applyToList(adapter, m, data, options.queryParameters);
        }
        for (var i = 0; i < data.length; i++) {
          final item = data[i];
          if (item is Map) {
            data[i] = _withBalance(adapter, _withChildren(adapter, item.cast<String, dynamic>(), children, includeChildList: false), all);
          }
        }
        return {...json, 'data': data};
      }

      if (detail != null && json['data'] is Map) {
        var record = (json['data'] as Map).cast<String, dynamic>();
        for (final m in own) {
          if (m.op == 'update' && m.targetIds.contains(detail)) record = adapter.applyPatch(record, m.body);
        }
        return {...json, 'data': _withBalance(adapter, _withChildren(adapter, record, children, includeChildList: true), all)};
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

  /// Fold queued contributions/repayments into their goal/loan: move its total
  /// and, on the detail view, add/edit/remove them in its list.
  Map<String, dynamic> _withChildren(
    EntityAdapter parent,
    Map<String, dynamic> record,
    List<PendingMutation> children, {
    required bool includeChildList,
  }) {
    final child = parent.childAdapter;
    if (child == null || children.isEmpty) return record;
    final id = record['id']?.toString();
    final mine = children.where((m) => m.effect['parent_id']?.toString() == id).toList();
    if (mine.isEmpty) return record;

    var next = {...record};
    var delta = 0;
    List<dynamic>? list = includeChildList && next[child.childKey] is List ? List<dynamic>.from(next[child.childKey] as List) : null;

    for (final m in mine) {
      delta += (m.effect['delta_minor'] as num?)?.toInt() ?? 0;
      if (list == null) continue;
      switch (m.op) {
        case 'create':
          final r = m.effect['record'];
          if (r is Map && !list.any((e) => e is Map && e['id']?.toString() == r['id']?.toString())) list.insert(0, r.cast<String, dynamic>());
        case 'update':
          for (var i = 0; i < list.length; i++) {
            final item = list[i];
            if (item is Map && m.targetIds.contains(item['id']?.toString())) {
              list[i] = child.applyPatch(item.cast<String, dynamic>(), m.body);
            }
          }
        case 'delete':
          list.removeWhere((e) => e is Map && m.targetIds.contains(e['id']?.toString()));
      }
    }
    if (list != null) next[child.childKey] = list;
    return parent.adjustForChildren(next, delta);
  }

  /// A detail response for a record that exists only locally (created offline,
  /// never fetched), built from its queued create plus later edits. Null when
  /// [options] is not such a request.
  Future<Map<String, dynamic>?> pendingDetail(RequestOptions options, String userId) async {
    for (final adapter in kEntityAdapters) {
      final id = adapter.detailId(options.path);
      if (id == null) continue;
      final all = await mutations.all(userId);
      Map<String, dynamic>? record;
      for (final m in all.where((m) => m.entity == adapter.entity)) {
        if (m.op == 'create' && m.targetIds.contains(id) && m.effect['record'] is Map) {
          record = (m.effect['record'] as Map).cast<String, dynamic>();
        } else if (record != null && m.op == 'update' && m.targetIds.contains(id)) {
          record = adapter.applyPatch(record, m.body);
        } else if (m.op == 'delete' && m.targetIds.contains(id)) {
          return null;
        }
      }
      if (record == null) return null;
      final childEntity = adapter.childAdapter?.entity;
      final children = childEntity == null ? <PendingMutation>[] : all.where((m) => m.entity == childEntity).toList();
      return {'data': _withBalance(adapter, _withChildren(adapter, record, children, includeChildList: true), all)};
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

      final all = await mutations.all(userId);
      var current = record;
      for (final m in all.where((m) => m.entity == adapter.entity)) {
        if (m.op == 'update' && m.targetIds.contains(id)) current = adapter.applyPatch(current, m.body);
        if (m.op == 'delete' && m.targetIds.contains(id)) return null;
      }
      final childEntity = adapter.childAdapter?.entity;
      final children = childEntity == null ? <PendingMutation>[] : all.where((m) => m.entity == childEntity).toList();
      return {'data': _withBalance(adapter, _withChildren(adapter, current, children, includeChildList: true), all)};
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

  /// Versions of the contributions/repayments nested in a goal/loan detail.
  /// Returns `{childEntity: {id: updated_at}}`; empty for other responses.
  static Map<String, Map<String, String>> childVersionsIn(String path, dynamic json) {
    for (final adapter in kEntityAdapters) {
      final child = adapter.childAdapter;
      if (child == null || adapter.detailId(path) == null || json is! Map) continue;
      final data = json['data'];
      final list = data is Map ? data[child.childKey] : null;
      if (list is! List) return const {};
      final out = <String, String>{};
      for (final item in list) {
        if (item is Map && item['id'] != null && item['updated_at'] != null) {
          out[item['id'].toString()] = item['updated_at'].toString();
        }
      }
      return out.isEmpty ? const {} : {child.entity: out};
    }
    return const {};
  }
}
