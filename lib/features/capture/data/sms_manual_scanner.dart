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
          'Offline or not signed in — will retry',
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
          ? 'Offline — ${result.pending} queued, will sync automatically'
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
