import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../env/app_env.dart';
import 'cache_store.dart';
import 'mutation_store.dart';

/// Something the user should know about after a sync: a change that could not be
/// applied (the server's version was kept) or was rejected.
class SyncNotice {
  const SyncNotice({required this.message, required this.atMs, this.kind = 'conflict'});

  /// conflict | missing | rejected
  final String kind;
  final String message;
  final int atMs;

  Map<String, dynamic> toJson() => {'kind': kind, 'message': message, 'at': atMs};

  factory SyncNotice.fromJson(Map<String, dynamic> j) => SyncNotice(
        kind: j['kind']?.toString() ?? 'conflict',
        message: j['message']?.toString() ?? '',
        atMs: (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// Keeps the latest notices so they can be shown (and dismissed) in Settings.
class SyncNotices {
  static const _key = 'offline_sync_notices';
  static const _max = 20;

  static Future<List<SyncNotice>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // a background sync may have added some
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((e) => SyncNotice.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(SyncNotice n) async {
    final all = [n, ...await load()].take(_max).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Result of one [MutationSync.flush].
class MutationFlushResult {
  const MutationFlushResult({
    this.applied = 0,
    this.conflicts = 0,
    this.dropped = 0,
    this.remaining = 0,
    this.offline = false,
    this.busy = false,
  });

  final int applied;
  final int conflicts;
  final int dropped;
  final int remaining;
  final bool offline;
  final bool busy;

  bool get changedAnything => applied + conflicts + dropped > 0;
}

/// Replays queued changes to the API in the order they were made.
///
/// Each replay carries its `Idempotency-Key` (so a retry never duplicates) and,
/// for edits and deletes, the version the change was based on. The server always
/// wins: a change to something that was changed or removed elsewhere is dropped
/// and reported, never forced through.
class MutationSync {
  MutationSync({
    required this.store,
    Dio Function(String token)? dioFactory,
    Future<String?> Function()? tokenReader,
  })  : _dioFactory = dioFactory ?? _defaultDio,
        _tokenReader = tokenReader;

  static final MutationSync instance = MutationSync(store: EncryptedCacheStore.instance);

  static const _tokenKey = 'mulinda_auth_token';
  static const _lockStale = Duration(seconds: 90);

  final MutationStore store;
  final Dio Function(String token) _dioFactory;
  final Future<String?> Function()? _tokenReader;

  static Dio _defaultDio(String token) => Dio(BaseOptions(
        baseUrl: AppEnv.apiBaseUrl,
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (_) => true, // every status is handled explicitly below
      ));

  DateTime? _lockedAt;

  Future<String?> _token() async {
    final reader = _tokenReader;
    if (reader != null) return reader();
    final t = await const FlutterSecureStorage().read(key: _tokenKey);
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Send everything that is waiting, in order. Stops at the first change that
  /// has to wait (no network, server busy…) so later changes never overtake it.
  Future<MutationFlushResult> flush({void Function(int done, int total)? onProgress, int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final token = await _token();
    final queue = await store.allPending();
    if (token == null || queue.isEmpty) return MutationFlushResult(remaining: queue.length);

    // One flush at a time within this isolate (the server is idempotent, so a
    // concurrent flush in another isolate is wasteful but harmless).
    final locked = _lockedAt;
    if (locked != null && DateTime.now().difference(locked) < _lockStale) {
      return MutationFlushResult(remaining: queue.length, busy: true);
    }
    _lockedAt = DateTime.now();

    var applied = 0, conflicts = 0, dropped = 0;
    var offline = false;
    final dio = _dioFactory(token);

    try {
      onProgress?.call(0, queue.length);
      for (var i = 0; i < queue.length; i++) {
        final m = queue[i];
        if (m.nextRetryMs > now) break; // backing off — hold back everything after it

        late final Response<dynamic> res;
        try {
          res = await dio.request<dynamic>(
            m.path,
            data: m.method == 'DELETE' && m.body.isEmpty ? null : m.body,
            options: Options(method: m.method, headers: {
              'Idempotency-Key': m.id,
              if (m.baseUpdatedAt != null) 'X-Base-Updated-At': m.baseUpdatedAt,
            }),
          );
        } on DioException {
          offline = true; // no response at all: network down or timed out
          await _retryLater(m, 'No connection');
          break;
        }

        final status = res.statusCode ?? 0;
        final outcome = await _handle(m, status, res.data);
        if (outcome == _Outcome.stop) {
          await _retryLater(m, 'HTTP $status');
          break;
        }
        if (outcome == _Outcome.halt) break; // e.g. 401: keep everything, try after login
        await store.remove(m.id);
        switch (outcome) {
          case _Outcome.applied:
            applied++;
          case _Outcome.conflict:
            conflicts++;
          case _Outcome.dropped:
            dropped++;
          default:
            break;
        }
        onProgress?.call(i + 1, queue.length);
      }
    } finally {
      _lockedAt = null;
    }

    return MutationFlushResult(
      applied: applied,
      conflicts: conflicts,
      dropped: dropped,
      remaining: await store.count(),
      offline: offline,
    );
  }

  Future<_Outcome> _handle(PendingMutation m, int status, dynamic data) async {
    if (status >= 200 && status < 300) return _Outcome.applied;
    final code = data is Map ? data['code']?.toString() : null;
    final message = data is Map ? data['message']?.toString() : null;

    if (status == 401) return _Outcome.halt;
    if (status == 409 && code == 'request_in_progress') return _Outcome.stop;
    if (status >= 500 || status == 429 || status == 408 || status == 0) return _Outcome.stop;

    if (status == 409 && code == 'conflict') {
      await _notice('conflict', 'Your offline ${_describe(m)} wasn\'t applied because it was changed elsewhere. The latest version was kept.');
      return _Outcome.conflict;
    }
    if (status == 404) {
      if (m.op == 'delete') return _Outcome.applied; // already gone — same end result
      await _notice('missing', 'Your offline ${_describe(m)} wasn\'t applied because it no longer exists.');
      return _Outcome.dropped;
    }
    if (status == 422) {
      final errors = data is Map && data['errors'] is Map ? data['errors'] as Map : const {};
      // A create whose id is already taken was already applied by an earlier attempt.
      if (m.op == 'create' && errors.containsKey('id')) return _Outcome.applied;
      final reason = errors.isNotEmpty
          ? (errors.values.first is List && (errors.values.first as List).isNotEmpty ? (errors.values.first as List).first : errors.values.first).toString()
          : (message ?? 'it was not accepted');
      await _notice('rejected', 'Your offline ${_describe(m)} couldn\'t be saved: $reason');
      return _Outcome.dropped;
    }

    // Any other 4xx (403 …): not retryable.
    await _notice('rejected', 'Your offline ${_describe(m)} couldn\'t be saved${message != null ? ': $message' : '.'}');
    return _Outcome.dropped;
  }

  Future<void> _retryLater(PendingMutation m, String reason) async {
    final attempts = m.attempts + 1;
    final delaySeconds = math.min(30 * math.pow(2, attempts - 1).toInt(), 1800);
    await store.reschedule(
      m.id,
      attempts: attempts,
      nextRetryMs: DateTime.now().add(Duration(seconds: delaySeconds)).millisecondsSinceEpoch,
      error: reason,
    );
  }

  Future<void> _notice(String kind, String message) =>
      SyncNotices.add(SyncNotice(kind: kind, message: message, atMs: DateTime.now().millisecondsSinceEpoch));

  /// e.g. "new transaction", "edit to a goal", "deletion of a loan".
  static String _describe(PendingMutation m) {
    final what = switch (m.entity) {
      'transaction' => 'transaction',
      'goal' => 'goal',
      'loan' => 'loan',
      _ => 'item',
    };
    return switch (m.op) {
      'create' => 'new $what',
      'update' => 'edit to a $what',
      'delete' => 'deletion of a $what',
      _ => 'change to a $what',
    };
  }
}

enum _Outcome { applied, conflict, dropped, stop, halt }
