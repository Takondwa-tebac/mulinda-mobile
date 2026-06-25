import 'package:another_telephony/telephony.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/env/app_env.dart';

/// Background isolate entry point for incoming SMS. MUST be a top-level
/// function annotated with `vm:entry-point` so it survives tree-shaking and can
/// be invoked from the platform side when the app is backgrounded/killed.
@pragma('vm:entry-point')
Future<void> mulindaSmsBackgroundHandler(SmsMessage message) async {
  await SmsAutoCapture.ingestIfFinancial(message.body, message.address);
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
  // Must match TokenStorage._tokenKey — the background isolate has no Riverpod.
  static const _tokenKey = 'mulinda_auth_token';

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
    if (await isEnabled()) await _startListening();
  }

  /// Request SMS permission, enable, and start listening. Returns false if the
  /// user denied permission.
  Future<bool> enableAndStart() async {
    final granted = await _telephony.requestPhoneAndSmsPermissions ?? false;
    if (!granted) return false;
    await _setEnabled(true);
    await _startListening();
    return true;
  }

  /// Turn the feature off. Listeners are not re-registered on the next launch.
  Future<void> disable() => _setEnabled(false);

  Future<void> _startListening() async {
    try {
      _telephony.listenIncomingSms(
        onNewMessage: (SmsMessage m) => ingestIfFinancial(m.body, m.address),
        onBackgroundMessage: mulindaSmsBackgroundHandler,
        listenInBackground: true,
      );
    } catch (_) {
      // Unsupported platform (iOS/desktop) or permission revoked — ignore.
    }
  }

  /// Send an SMS to the ingest endpoint only if it looks financial. Used by
  /// both the foreground and background handlers; standalone (no Riverpod) so
  /// it works in the background isolate.
  static Future<void> ingestIfFinancial(String? body, String? sender) async {
    final text = (body ?? '').trim();
    if (text.isEmpty || !isFinancialSms(text)) return; // personal SMS stay on-device

    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) return; // not signed in

      final dio = Dio(BaseOptions(
        baseUrl: AppEnv.apiBaseUrl,
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ));
      await dio.post('/v1/sms', data: {
        'body': text,
        if (sender != null && sender.isNotEmpty) 'sender': sender,
      });
    } catch (_) {
      // Best-effort: never crash on a background message.
    }
  }

  /// Heuristic: does this SMS look like a money/transaction message? Mirrors the
  /// filter used by the manual inbox import.
  static bool isFinancialSms(String body) {
    final b = body.toLowerCase();
    const keywords = [
      'mwk', 'kwacha', 'airtel', 'mpamba', 'tnm', 'mo626',
      'received', 'sent', 'withdrawn', 'deposited', 'payment',
      'balance', 'transaction', 'national bank', 'standard bank',
      'fdh', 'nbs', 'paid', 'debited', 'credited',
    ];
    return keywords.any(b.contains);
  }
}
