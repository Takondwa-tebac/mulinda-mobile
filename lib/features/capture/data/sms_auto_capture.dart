import 'dart:developer' as developer;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart';
import 'sms_background_sync.dart';
import 'sms_capability.dart';
import 'sms_outbox.dart';

/// Debug-only trace of the SMS-capture pipeline. Shows in `flutter run` and
/// `adb logcat` under the `sms_capture` tag so a headed test can see exactly
/// which stage fired. Compiled out of release builds.
void smsCaptureLog(String message) {
  if (kDebugMode) developer.log(message, name: 'sms_capture');
}

/// Background isolate entry point for incoming SMS. MUST be a top-level
/// function annotated with `vm:entry-point` so it survives tree-shaking and can
/// be invoked from the platform side when the app is backgrounded/killed.
@pragma('vm:entry-point')
Future<void> mulindaSmsBackgroundHandler(SmsMessage message) async {
  smsCaptureLog('background SMS received from ${message.address}');
  await SmsAutoCapture.ingestIfFinancial(message.body, message.address, dateMs: message.date);
}

/// Opt-in automatic capture of *financial* SMS into the inbox for review.
///
/// Privacy: only messages that look like a financial transaction are ever sent
/// to the server (see [isFinancialSms]). Personal messages never leave the
/// device. The feature is off by default and toggled explicitly by the user
/// after an in-context explanation on the permissions screen.
class SmsAutoCapture {
  SmsAutoCapture._();
  static final SmsAutoCapture instance = SmsAutoCapture._();

  static const _prefKey = 'sms_auto_capture_enabled';

  final Telephony _telephony = Telephony.instance;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> _setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  /// Start listening if the user has enabled the feature (called at launch).
  Future<void> maybeStart() async {
    if (!SmsCapability.canReadSms) return;
    if (await isEnabled()) {
      await _startListening();
      await SmsBackgroundSync.startPeriodic();
    }
  }

  /// Request SMS permission, enable, and start listening. Returns false if the
  /// user denied permission.
  Future<bool> enableAndStart() async {
    if (!SmsCapability.canReadSms) return false;
    final granted = await _telephony.requestPhoneAndSmsPermissions ?? false;
    if (!granted) return false;
    await _setEnabled(true);
    await _startListening();
    await SmsBackgroundSync.startPeriodic();
    return true;
  }

  /// Turn the feature off. Listeners are not re-registered on the next launch.
  Future<void> disable() async {
    await _setEnabled(false);
    await SmsBackgroundSync.stop();
  }

  Future<void> _startListening() async {
    try {
      _telephony.listenIncomingSms(
        onNewMessage: (SmsMessage m) {
          smsCaptureLog('foreground SMS received from ${m.address}');
          ingestIfFinancial(m.body, m.address, dateMs: m.date);
        },
        onBackgroundMessage: mulindaSmsBackgroundHandler,
        listenInBackground: true,
      );
      smsCaptureLog('listening for incoming SMS (foreground + background)');
    } catch (e) {
      // Unsupported platform (iOS/desktop) or permission revoked — ignore.
      smsCaptureLog('listen failed (unsupported platform or no permission): $e');
    }
  }

  /// Capture an SMS only if it looks financial: queue it durably, then sync.
  /// Used by both the foreground and background handlers; standalone (no
  /// Riverpod) so it works in the background isolate.
  ///
  /// Online this is one round trip (instant, as before). Offline the SMS stays
  /// in the outbox, the user gets a local notification, and it syncs — exactly
  /// once, the server is idempotent — as soon as a trigger fires with a
  /// connection (next SMS, app open/resume, or the foreground retry timer).
  static Future<void> ingestIfFinancial(
    String? body,
    String? sender, {
    int? dateMs,
  }) async {
    final text = (body ?? '').trim();
    if (text.isEmpty) return;

    final financial = isFinancialSms(text);
    smsCaptureLog('from ${sender ?? '?'} — financial=$financial');
    if (!financial) return; // personal SMS stay on-device

    try {
      await SmsOutbox.instance.enqueue(
        body: text,
        sender: sender,
        receivedAtMs: dateMs ?? DateTime.now().millisecondsSinceEpoch,
        origin: SmsOrigin.live,
      );
      final result = await SmsOutbox.instance.flush();
      smsCaptureLog(
        'flush: created=${result.created} dup=${result.duplicates} '
        'pending=${result.pending} offline=${result.offline}',
      );
      if (result.offline) await NotificationService.showSmsQueued(text);
      // Anything left in the outbox syncs as soon as the phone is online,
      // even if the app stays closed.
      if (result.pending > 0) await SmsBackgroundSync.syncWhenOnline();
    } catch (e) {
      // Best-effort: never crash on a background message.
      smsCaptureLog('capture error: $e');
    }
  }

  /// An amount of money: `MWK 5,000`, `MK5000`, `K 200.50` or `5,000 MWK`.
  static final _amount = RegExp(
    r'\b(?:mwk|mk|k)\s?\d[\d,]*(?:\.\d+)?|\d[\d,]*(?:\.\d+)?\s?(?:mwk|kwacha)\b',
    caseSensitive: false,
  );

  /// Heuristic: does this SMS look like a money/transaction message? It needs an
  /// amount of money as well as a money word, so telecom notices and promotions that
  /// only say "balance" or "received" stay on the phone instead of being sent to the
  /// server (where they would count against the free capture limit). The server
  /// decides whether it is really a completed transaction.
  static bool isFinancialSms(String body) {
    final b = body.toLowerCase();
    if (!_amount.hasMatch(b)) return false;
    const keywords = [
      'mwk', 'kwacha', 'airtel', 'mpamba', 'tnm', 'mo626',
      'received', 'sent', 'withdrawn', 'deposited', 'payment',
      'balance', 'transaction', 'national bank', 'standard bank',
      'fdh', 'nbs', 'paid', 'debited', 'credited',
    ];
    return keywords.any(b.contains);
  }
}
