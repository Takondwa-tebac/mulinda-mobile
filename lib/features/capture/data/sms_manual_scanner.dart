import 'dart:developer' as developer;
import 'package:another_telephony/telephony.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/env/app_env.dart';

void smsScanLog(String message) {
  if (kDebugMode) developer.log(message, name: 'sms_scan');
}

/// Manual SMS scanner for users to trigger SMS scanning on demand
/// and for app-open scanning to catch missed SMS
class SmsManualScanner {
  SmsManualScanner._();
  static final SmsManualScanner instance = SmsManualScanner._();

  static const _tokenKey = 'mulinda_auth_token';
  final Telephony _telephony = Telephony.instance;

  /// Scan SMS inbox for financial messages and send to API
  /// Called when user manually triggers scan or on app open
  Future<ScanResult> scanFinancialSms() async {
    smsScanLog('Starting manual SMS scan');

    try {
      final granted = await _telephony.requestSmsPermissions ?? false;
      if (!granted) {
        smsScanLog('SMS permission denied');
        return ScanResult.success(0, 0, 'Permission denied');
      }

      final messages = await _telephony.getInboxSms();
      final financialSms = messages.where((msg) => _isFinancialSms(msg.body ?? '')).toList();

      smsScanLog('Found ${financialSms.length} financial SMS out of ${messages.length} total');

      if (financialSms.isEmpty) {
        return ScanResult.success(0, 0, 'No financial SMS found');
      }

      final token = await const FlutterSecureStorage().read(key: _tokenKey);
      if (token == null || token.isEmpty) {
        smsScanLog('User not authenticated');
        return ScanResult.success(0, 0, 'Not logged in');
      }

      int processed = 0;
      int failed = 0;

      final dio = Dio(BaseOptions(
        baseUrl: AppEnv.apiBaseUrl,
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ));

      for (final msg in financialSms) {
        try {
          await dio.post('/v1/sms', data: {
            'body': msg.body ?? '',
            if (msg.sender != null && msg.sender!.isNotEmpty) 'sender': msg.sender,
          });
          processed++;
          smsScanLog('Processed SMS from ${msg.sender}');
        } on DioException catch (e) {
          failed++;
          smsScanLog('Failed to process SMS: ${e.response?.statusCode} ${e.message}');
        } catch (e) {
          failed++;
          smsScanLog('Error processing SMS: $e');
        }
      }

      smsScanLog('Scan complete: $processed processed, $failed failed');
      return ScanResult.success(processed, failed, 'Scan completed');
    } catch (e) {
      smsScanLog('Scan failed: $e');
      return ScanResult.error('Scan failed: $e');
    }
  }

  /// Check if SMS body appears to be financial
  bool _isFinancialSms(String body) {
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

class ScanResult {
  final bool success;
  final int processed;
  final int failed;
  final String message;

  ScanResult.success(this.processed, this.failed, this.message) : success = true;
  ScanResult.error(this.message) : success = false, processed = 0, failed = 0;
}
