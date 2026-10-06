import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/env/app_env.dart';
import 'sms_auto_capture.dart' show smsCaptureLog;

/// Where an outbox item came from. `live` = received while the app was
/// listening (never old history); `scan` = found by reading the inbox, which the
/// server restricts to messages after the user's baseline.
enum SmsOrigin { live, scan }

/// Outcome of a [SmsOutbox.flush].
class FlushResult {
  const FlushResult({
    this.created = 0,
    this.duplicates = 0,
    this.skipped = 0,
    this.limitReached = 0,
    this.failed = 0,
    this.offline = false,
    this.pending = 0,
  });

  final int created;
  final int duplicates;
  final int skipped;
  final int limitReached;
  final int failed;

  /// True when the server could not be reached (no/poor connection).
  final bool offline;

  /// Items still waiting in the outbox after this flush.
  final int pending;
}

/// Durable, idempotent queue for captured SMS.
///
/// Every captured financial SMS is written to the outbox *first* and removed
/// only once the server confirms it (created / duplicate / skipped). That makes
/// capture safe offline, across crashes and app kills, and safe to retry:
/// the server de-duplicates on `client_id` and on the message content hash.
///
/// One small JSON file per message (written via temp-file + rename) so the
/// background isolate and the UI isolate never contend over a shared file.
class SmsOutbox {
  SmsOutbox._();
  static final SmsOutbox instance = SmsOutbox._();

  // Must match TokenStorage._tokenKey — the background isolate has no Riverpod.
  static const _tokenKey = 'mulinda_auth_token';
  static const _batchSize = 50;
  static const _lockStale = Duration(seconds: 90);
  static const _limitBackoff = Duration(hours: 6);
  static const _maxAttempts = 8;

  /// Stable, content-derived id so capturing the same SMS twice (live listener
  /// and inbox scan) yields one outbox entry and one server record.
  static String clientIdFor(String? sender, int receivedAtMs, String body) {
    // FNV-1a (32-bit) — deterministic across runs, unlike String.hashCode.
    var h = 0x811c9dc5;
    for (final unit in utf8.encode('${sender ?? ''}|${body.trim()}')) {
      h ^= unit;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return '$receivedAtMs-${h.toRadixString(16)}';
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/sms_outbox');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Queue a captured SMS. Idempotent: re-queuing the same SMS is a no-op.
  Future<String> enqueue({
    required String body,
    String? sender,
    required int receivedAtMs,
    SmsOrigin origin = SmsOrigin.live,
  }) async {
    final id = clientIdFor(sender, receivedAtMs, body);
    final dir = await _dir();
    final file = File('${dir.path}/$id.json');
    if (file.existsSync()) return id;

    final tmp = File('${dir.path}/$id.tmp');
    await tmp.writeAsString(jsonEncode({
      'client_id': id,
      'body': body,
      if (sender != null && sender.isNotEmpty) 'sender': sender,
      'received_at':
          DateTime.fromMillisecondsSinceEpoch(receivedAtMs, isUtc: true).toIso8601String(),
      'source': origin.name,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'next_retry_ms': 0,
    }));
    await tmp.rename(file.path);
    return id;
  }

  Future<List<File>> _files() async {
    final dir = await _dir();
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
  }

  Future<int> pendingCount() async => (await _files()).length;

  /// Drop everything — call on sign-out so one account's SMS are never synced
  /// to another.
  Future<void> clear() async {
    try {
      final dir = await _dir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  Dio _client(String token) => Dio(BaseOptions(
        baseUrl: AppEnv.apiBaseUrl,
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));

  Future<String?> _token() async {
    final token = await const FlutterSecureStorage().read(key: _tokenKey);
    return (token == null || token.isEmpty) ? null : token;
  }

  /// Server baseline (earliest `received_at` an inbox scan may submit), or null
  /// when offline / signed out.
  Future<DateTime?> fetchBaseline() async {
    final token = await _token();
    if (token == null) return null;
    try {
      final res = await _client(token).get<Map<String, dynamic>>('/v1/sms/sync-state');
      final iso = (res.data?['data'] as Map?)?['baseline_at']?.toString();
      return iso == null ? null : DateTime.tryParse(iso);
    } on DioException {
      return null;
    }
  }

  // ---- Lock (best-effort, avoids two isolates flushing at once) ------------

  Future<bool> _acquireLock() async {
    final dir = await _dir();
    final lock = File('${dir.path}/flush.lock');
    if (lock.existsSync()) {
      final age = DateTime.now().difference(lock.lastModifiedSync());
      if (age < _lockStale) return false;
    }
    await lock.writeAsString(DateTime.now().toIso8601String());
    return true;
  }

  Future<void> _releaseLock() async {
    try {
      final dir = await _dir();
      final lock = File('${dir.path}/flush.lock');
      if (lock.existsSync()) lock.deleteSync();
    } catch (_) {}
  }

  /// Send everything that is due. Safe to call from any trigger, any isolate,
  /// any number of times: the server is idempotent, so the worst case is a
  /// redundant request.
  Future<FlushResult> flush() async {
    final token = await _token();
    if (token == null) return FlushResult(pending: await pendingCount());
    if (!await _acquireLock()) return FlushResult(pending: await pendingCount());

    var created = 0, duplicates = 0, skipped = 0, limit = 0, failed = 0;
    var offline = false;

    try {
      final dio = _client(token);
      final now = DateTime.now().millisecondsSinceEpoch;

      final due = <Map<String, dynamic>>[];
      for (final f in await _files()) {
        try {
          final item = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          if (((item['next_retry_ms'] as num?) ?? 0) <= now) due.add(item);
        } catch (_) {
          // Corrupt entry — drop it rather than blocking the queue.
          f.deleteSync();
        }
      }
      due.sort((a, b) => ((a['created_ms'] as num?) ?? 0).compareTo((b['created_ms'] as num?) ?? 0));

      for (var i = 0; i < due.length && !offline; i += _batchSize) {
        final chunk = due.sublist(i, math.min(i + _batchSize, due.length));
        try {
          final res = await dio.post<Map<String, dynamic>>('/v1/sms/sync', data: {
            'items': [
              for (final it in chunk)
                {
                  'client_id': it['client_id'],
                  'body': it['body'],
                  if (it['sender'] != null) 'sender': it['sender'],
                  'received_at': it['received_at'],
                  'source': it['source'] ?? 'scan',
                },
            ],
          });
          final results = ((res.data?['data'] as Map?)?['results'] as List?) ?? const [];
          for (final r in results.cast<Map>()) {
            final id = r['client_id']?.toString();
            final item = chunk.firstWhere((e) => e['client_id'] == id, orElse: () => const {});
            if (item.isEmpty) continue;
            switch (r['status']?.toString()) {
              case 'created':
                created++;
                await _remove(id!);
              case 'duplicate':
                duplicates++;
                await _remove(id!);
              case 'skipped':
                skipped++;
                await _remove(id!);
              case 'limit_reached':
                limit++;
                await _reschedule(item, _limitBackoff, countAttempt: false);
              default:
                failed++;
                await _reschedule(item, _backoff(item));
            }
          }
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          if (status == null) {
            // No connection / timeout: stop, keep everything, retry on next trigger.
            offline = true;
          } else if (status == 401) {
            break; // signed out / token expired — keep items for the next login
          } else {
            failed += chunk.length;
            for (final it in chunk) {
              await _reschedule(it, _backoff(it));
            }
          }
          smsCaptureLog('outbox flush: ${status ?? e.type.name}');
        }
      }
    } finally {
      await _releaseLock();
    }

    return FlushResult(
      created: created,
      duplicates: duplicates,
      skipped: skipped,
      limitReached: limit,
      failed: failed,
      offline: offline,
      pending: await pendingCount(),
    );
  }

  Duration _backoff(Map<String, dynamic> item) {
    final attempts = ((item['attempts'] as num?) ?? 0).toInt() + 1;
    // 30s, 1m, 2m, 4m … capped at 30 min.
    return Duration(seconds: math.min(30 * math.pow(2, attempts - 1).toInt(), 1800));
  }

  Future<void> _remove(String id) async {
    final dir = await _dir();
    final f = File('${dir.path}/$id.json');
    if (f.existsSync()) f.deleteSync();
  }

  Future<void> _reschedule(
    Map<String, dynamic> item,
    Duration delay, {
    bool countAttempt = true,
  }) async {
    final attempts = ((item['attempts'] as num?) ?? 0).toInt() + (countAttempt ? 1 : 0);
    final id = item['client_id'].toString();
    if (countAttempt && attempts >= _maxAttempts) {
      await _remove(id); // poison item — stop retrying
      return;
    }
    item['attempts'] = attempts;
    item['next_retry_ms'] = DateTime.now().add(delay).millisecondsSinceEpoch;
    final dir = await _dir();
    final tmp = File('${dir.path}/$id.tmp');
    await tmp.writeAsString(jsonEncode(item));
    await tmp.rename('${dir.path}/$id.json');
  }
}
