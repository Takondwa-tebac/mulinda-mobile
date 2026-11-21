import 'dart:developer' as developer;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sms_auto_capture.dart';
import 'sms_outbox.dart';

void smsScanLog(String message) {
  if (kDebugMode) developer.log(message, name: 'sms_scan');
}

/// Catch-up scan for SMS the live listener missed (app killed, phone off,
/// listener not yet enabled…).
///
/// Safe for existing users: the server decides the earliest message it will
/// accept (the user's *baseline*), so updating the app never re-imports
/// history. The scan also keeps a cursor, so each run reads only inbox messages
/// newer than the last run instead of the whole inbox.
class SmsManualScanner {
  SmsManualScanner._();
  static final SmsManualScanner instance = SmsManualScanner._();

  static const _cursorKey = 'sms_scan_cursor_ms';
  final Telephony _telephony = Telephony.instance;

  /// Scan the inbox for financial SMS newer than the baseline/cursor, queue them
  /// in the outbox and sync.
  ///
  /// [manual] is true when the user tapped Scan: it may prompt for permission
  /// and runs even if auto-capture is off. The launch scan (`manual: false`)
  /// never prompts and does nothing unless the user opted in to auto-capture.
  Future<ScanResult> scanFinancialSms({bool manual = false}) async {
    smsScanLog('Starting SMS scan (manual=$manual)');

    try {
      if (!manual && !await SmsAutoCapture.isEnabled()) {
        return ScanResult.success(0, 0, 'Auto-capture is off');
      }

      final granted = manual
          ? (await _telephony.requestSmsPermissions ?? false)
          : await Permission.sms.isGranted;
      if (!granted) {
        return ScanResult.success(0, 0, 'SMS permission not granted');
      }

      // Always push anything already queued first (offline captures).
      final preFlush = await SmsOutbox.instance.flush();

      final baseline = await SmsOutbox.instance.fetchBaseline();
      if (baseline == null) {
        return ScanResult.success(
          preFlush.created,
          preFlush.failed,
          'Offline or not signed in - will retry',
          preFlush.duplicates + preFlush.skipped,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final cursor = prefs.getInt(_cursorKey) ?? 0;
      final sinceMs = cursor > baseline.millisecondsSinceEpoch
          ? cursor
          : baseline.millisecondsSinceEpoch;

      final messages = await _telephony.getInboxSms(
        filter: SmsFilter.where(SmsColumn.DATE).greaterThanOrEqualTo('$sinceMs'),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
      );
      final financial = messages
          .where((m) => SmsAutoCapture.isFinancialSms(m.body ?? ''))
          .toList();
      smsScanLog('Found ${financial.length} financial SMS of ${messages.length} since $sinceMs');

      var newest = cursor;
      for (final m in financial) {
        final date = m.date ?? DateTime.now().millisecondsSinceEpoch;
        await SmsOutbox.instance.enqueue(
          body: (m.body ?? '').trim(),
          sender: m.address,
          receivedAtMs: date,
          origin: SmsOrigin.scan,
        );
        if (date > newest) newest = date;
      }
      for (final m in messages) {
        final date = m.date ?? 0;
        if (date > newest) newest = date;
      }

      final result = await SmsOutbox.instance.flush();

      // Only advance the cursor when everything reached the server, so a failed
      // sync is re-read next time (the server de-duplicates the overlap).
      if (!result.offline && result.failed == 0 && newest > cursor) {
        await prefs.setInt(_cursorKey, newest);
      }

      final message = result.offline
          ? 'Offline - ${result.pending} queued, will sync automatically'
          : 'Scan completed';
      return ScanResult.success(
        result.created + preFlush.created,
        result.failed,
        message,
        result.duplicates + result.skipped,
      );
    } catch (e) {
      smsScanLog('Scan failed: $e');
      return ScanResult.error('Scan failed: $e');
    }
  }
}

/// The first-run history import: money messages from the last 30 days (never
/// before the server baseline, which for a new account is that same window),
/// sent through the outbox like any other capture.
class FirstRunImport {
  FirstRunImport._();
  static final FirstRunImport instance = FirstRunImport._();

  static const window = Duration(days: 30);

  final Telephony _telephony = Telephony.instance;

  /// Where the import starts: 30 days ago, or the server baseline if later.
  static DateTime startFrom(DateTime now, DateTime? baseline) {
    final windowStart = now.subtract(window);
    return baseline != null && baseline.isAfter(windowStart) ? baseline : windowStart;
  }

  /// Financial inbox messages since [startFrom], oldest first. Needs the SMS
  /// permission; personal messages are filtered out on the phone.
  Future<List<SmsMessage>> findMessages() async {
    final baseline = await SmsOutbox.instance.fetchBaseline();
    final since = startFrom(DateTime.now(), baseline).millisecondsSinceEpoch;
    final messages = await _telephony.getInboxSms(
      filter: SmsFilter.where(SmsColumn.DATE).greaterThanOrEqualTo('$since'),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
    );
    return messages.where((m) => SmsAutoCapture.isFinancialSms(m.body ?? '')).toList();
  }

  /// Queue [messages] and sync them. The scan cursor moves past them once
  /// they all reached the server, so the launch scan does not read them again.
  Future<FlushResult> send(List<SmsMessage> messages, {void Function(int done, int total)? onProgress}) async {
    var newest = 0;
    for (final m in messages) {
      final date = m.date ?? DateTime.now().millisecondsSinceEpoch;
      await SmsOutbox.instance.enqueue(
        body: (m.body ?? '').trim(),
        sender: m.address,
        receivedAtMs: date,
        origin: SmsOrigin.scan,
      );
      if (date > newest) newest = date;
    }
    var result = await SmsOutbox.instance.flush(onProgress: onProgress);
    // Another sync (the launch scan, the retry timer) holds the outbox: wait
    // for it rather than reporting nothing sent.
    for (var i = 0; result.busy && i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      result = await SmsOutbox.instance.flush(onProgress: onProgress);
    }
    if (!result.offline && result.failed == 0 && newest > 0) {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(SmsManualScanner._cursorKey) ?? 0) < newest) {
        await prefs.setInt(SmsManualScanner._cursorKey, newest);
      }
    }
    return result;
  }
}

class ScanResult {
  final bool success;
  final int processed;
  final int failed;
  final int skipped;
  final String message;

  ScanResult.success(this.processed, this.failed, this.message, [this.skipped = 0])
    : success = true;
  ScanResult.error(this.message) : success = false, processed = 0, failed = 0, skipped = 0;
}
