import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/env/app_env.dart';
import '../../../core/network/api_exception.dart';
import 'receipt_scanner.dart';

/// What became of one receipt upload.
sealed class ReceiptUpload {
  const ReceiptUpload();
}

/// The server has it: [result] says whether it is ready to review.
class ReceiptUploaded extends ReceiptUpload {
  const ReceiptUploaded(this.result);
  final ReceiptScanResult result;
}

/// Not sent yet (no connection, timeout, server trouble, signed out, or
/// another upload running): it stays queued and is retried.
class ReceiptQueued extends ReceiptUpload {
  const ReceiptQueued();
}

/// The server refused it for good (not allowed, invalid): dropped.
class ReceiptRejected extends ReceiptUpload {
  const ReceiptRejected(this.error);
  final ApiException error;
}

/// Sends one queued receipt. The real one posts multipart to the API; tests
/// fake it.
abstract class ReceiptUploader {
  Future<ReceiptScanResult> upload(File image, Map<String, dynamic> item);
}

class DioReceiptUploader implements ReceiptUploader {
  DioReceiptUploader(this.dio);

  final Dio dio;

  @override
  Future<ReceiptScanResult> upload(File image, Map<String, dynamic> item) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(image.path),
      'client_id': item['client_id'],
      if (item['draft'] != null) 'draft': jsonEncode(item['draft']),
      if (item['ocr_lines'] != null) 'ocr_lines': jsonEncode(item['ocr_lines']),
      if (item['metrics'] != null) 'metrics': jsonEncode(item['metrics']),
    });
    final res = await dio.post('/v1/receipt-scans', data: form);
    final data = (res.data is Map ? res.data['data'] : null) as Map?;
    return ReceiptScanResult.fromJson(data?.cast<String, dynamic>() ?? const {});
  }
}

/// Receipts waiting to upload, kept on disk so none is lost to a dropped
/// connection, a closed app or a phone restart. Mirrors the SMS outbox: one
/// folder per receipt (the image and a JSON record) in app support storage, a
/// lock so the app and the background worker never send at once, backoff on
/// failure, and the server's idempotent `client_id` so a resend is harmless.
///
/// Triggers: the scan screen sends at once; the app retries on reconnect, on
/// resume and every 2 minutes while open; on Android the background worker
/// retries with the app closed.
class ReceiptOutbox {
  ReceiptOutbox({this.uploader, Future<Directory> Function()? root, this.now = DateTime.now}) : _root = root;

  static final ReceiptOutbox instance = ReceiptOutbox();

  /// Null: built per send from the stored sign-in token (works in the
  /// background isolate, which has no Riverpod).
  final ReceiptUploader? uploader;
  final Future<Directory> Function()? _root;
  final DateTime Function() now;

  // Must match TokenStorage._tokenKey.
  static const _tokenKey = 'mulinda_auth_token';
  static const _lockStale = Duration(minutes: 3);

  /// At most this many receipts wait (~1 MB each), so a phone offline for
  /// weeks doesn't fill its storage.
  static const maxQueued = 30;

  /// A receipt that could not be sent for this long is dropped.
  static const maxAge = Duration(days: 30);

  Future<Directory> _dir() async {
    final base = _root != null ? await _root() : await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/receipt_outbox');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<List<Directory>> _items() async =>
      (await _dir()).listSync().whereType<Directory>().where((d) => File('${d.path}/item.json').existsSync()).toList();

  Future<int> pendingCount() async => (await _items()).length;

  /// Queue a receipt: the image is copied in, so the caller may delete its own
  /// temporary files. Returns false when the queue is full.
  Future<bool> enqueue({
    required String imagePath,
    required String clientId,
    Map<String, dynamic>? draft,
    List<Map<String, dynamic>>? ocrLines,
    Map<String, dynamic>? metrics,
  }) async {
    final dir = await _dir();
    final itemDir = Directory('${dir.path}/$clientId');
    if (File('${itemDir.path}/item.json').existsSync()) return true;
    if ((await _items()).length >= maxQueued) return false;

    itemDir.createSync(recursive: true);
    final ext = imagePath.contains('.') ? imagePath.substring(imagePath.lastIndexOf('.')) : '.jpg';
    await File(imagePath).copy('${itemDir.path}/image$ext');
    // Write the record last and atomically: an item without item.json is
    // incomplete and gets cleaned up.
    final tmp = File('${itemDir.path}/item.tmp');
    await tmp.writeAsString(jsonEncode({
      'client_id': clientId,
      'image': 'image$ext',
      'draft': draft,
      'ocr_lines': ocrLines,
      'metrics': metrics,
      'created_ms': now().millisecondsSinceEpoch,
      'attempts': 0,
      'next_retry_ms': 0,
    }));
    await tmp.rename('${itemDir.path}/item.json');
    return true;
  }

  /// Send one receipt now (the scan screen, right after queuing it).
  Future<ReceiptUpload> send(String clientId) async {
    final dir = Directory('${(await _dir()).path}/$clientId');
    if (!File('${dir.path}/item.json').existsSync()) return const ReceiptQueued();
    return _withLock(() async {
      final client = await _client();
      if (client == null) return const ReceiptQueued();
      try {
        return await _send(dir, client.$1);
      } finally {
        client.$2?.close();
      }
    }, busy: const ReceiptQueued());
  }

  /// Send everything due, oldest first; stops at the first sign of no
  /// connection. Safe to call from any trigger and either isolate.
  Future<int> flush() async {
    await _cleanUp();
    return _withLock(() async {
      final client = await _client();
      if (client == null) return 0;
      var sent = 0;
      try {
        final due = <(Directory, Map<String, dynamic>)>[];
        for (final d in await _items()) {
          final item = _read(d);
          if (item == null) continue;
          if (((item['next_retry_ms'] as num?) ?? 0) <= now().millisecondsSinceEpoch) due.add((d, item));
        }
        due.sort((a, b) => ((a.$2['created_ms'] as num?) ?? 0).compareTo((b.$2['created_ms'] as num?) ?? 0));
        for (final (d, _) in due) {
          final outcome = await _send(d, client.$1);
          if (outcome is ReceiptUploaded) sent++;
          if (outcome is ReceiptQueued && _lastWasOffline) break;
        }
      } finally {
        client.$2?.close();
      }
      return sent;
    }, busy: 0);
  }

  /// Drop everything: on sign-out, so one account's receipts never upload to
  /// another.
  Future<void> clear() async {
    try {
      final dir = await _dir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  bool _lastWasOffline = false;

  Future<ReceiptUpload> _send(Directory dir, ReceiptUploader uploader) async {
    _lastWasOffline = false;
    final item = _read(dir);
    if (item == null) return const ReceiptQueued();
    final image = File('${dir.path}/${item['image']}');
    if (!image.existsSync()) {
      _delete(dir);
      return const ReceiptQueued();
    }
    try {
      final result = await uploader.upload(image, item);
      _delete(dir);
      return ReceiptUploaded(result);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final error = ApiException.fromDio(e);
      // The AI's quota is spent (an upload without the phone's reading): the
      // server holds AI work back for a while, so the user is offered to add
      // it by hand instead of a retry that would fail the same way.
      final aiBusy = error.code == 'ai_rate_limited';
      if (!aiBusy && (status == null || status == 401 || status == 408 || status == 429 || status >= 500)) {
        // No connection, signed out, rate limited or server trouble: retry.
        _lastWasOffline = status == null;
        await _reschedule(dir, item, '${status ?? e.type.name}');
        return const ReceiptQueued();
      }
      _delete(dir); // refused for good (402, 413, 422 ...): retrying won't help
      return ReceiptRejected(error);
    }
  }

  Future<(ReceiptUploader, Dio?)?> _client() async {
    if (uploader != null) return (uploader!, null);
    final token = await const FlutterSecureStorage().read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;
    final dio = Dio(BaseOptions(
      baseUrl: AppEnv.apiBaseUrl,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      connectTimeout: const Duration(seconds: 15),
      // A receipt image on a slow connection.
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 30),
    ));
    return (DioReceiptUploader(dio), dio);
  }

  Map<String, dynamic>? _read(Directory dir) {
    try {
      return (jsonDecode(File('${dir.path}/item.json').readAsStringSync()) as Map).cast<String, dynamic>();
    } catch (_) {
      _delete(dir); // corrupt: drop it rather than block the queue
      return null;
    }
  }

  Future<void> _reschedule(Directory dir, Map<String, dynamic> item, String error) async {
    final attempts = ((item['attempts'] as num?) ?? 0).toInt() + 1;
    // 30 s, 1, 2, 4 … minutes, capped at 6 hours.
    final wait = Duration(seconds: math.min(30 * math.pow(2, attempts - 1).toInt(), 6 * 3600));
    try {
      await File('${dir.path}/item.json').writeAsString(jsonEncode({
        ...item,
        'attempts': attempts,
        'next_retry_ms': now().add(wait).millisecondsSinceEpoch,
        'last_error': error,
      }));
    } catch (_) {}
  }

  /// Leftovers: incomplete items (no record), and receipts older than
  /// [maxAge].
  Future<void> _cleanUp() async {
    try {
      final cutoff = now().subtract(maxAge).millisecondsSinceEpoch;
      for (final d in (await _dir()).listSync().whereType<Directory>()) {
        if (!File('${d.path}/item.json').existsSync()) {
          // Give a concurrent enqueue a minute to finish writing.
          if (now().difference(d.statSync().modified) > const Duration(minutes: 1)) _delete(d);
          continue;
        }
        final item = _read(d);
        if (item != null && ((item['created_ms'] as num?) ?? 0) < cutoff) _delete(d);
      }
    } catch (_) {}
  }

  void _delete(Directory dir) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  Future<T> _withLock<T>(Future<T> Function() body, {required T busy}) async {
    final lock = File('${(await _dir()).path}/send.lock');
    if (lock.existsSync() && now().difference(lock.lastModifiedSync()) < _lockStale) return busy;
    try {
      await lock.writeAsString(now().toIso8601String());
      return await body();
    } finally {
      try {
        if (lock.existsSync()) lock.deleteSync();
      } catch (_) {}
    }
  }
}

final receiptOutboxProvider = Provider<ReceiptOutbox>((ref) => ReceiptOutbox.instance);

/// The device side of a scan's timing report: enough to tell an entry-level
/// phone from a flagship in the admin analytics. No identifiers.
class ScanDeviceInfo {
  ScanDeviceInfo._();

  static Future<Map<String, dynamic>>? _cached;

  static Future<Map<String, dynamic>> get() => _cached ??= _load();

  static Future<Map<String, dynamic>> _load() async {
    final info = <String, dynamic>{'os': defaultTargetPlatform.name};
    try {
      info['app_version'] = (await PackageInfo.fromPlatform()).version;
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        info.addAll({
          'device_model': '${a.manufacturer} ${a.model}',
          'os_version': '${a.version.sdkInt}',
          'ram_mb': a.physicalRamSize,
          'low_ram': a.isLowRamDevice,
        });
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        info.addAll({'device_model': i.utsname.machine, 'os_version': i.systemVersion, 'ram_mb': i.physicalRamSize});
      }
    } catch (_) {}
    return info;
  }
}
