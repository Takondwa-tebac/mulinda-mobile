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
      final financialSms = messages
          .where((msg) => _isFinancialSms(msg.body ?? ''))
          .toList();

      smsScanLog(
        'Found ${financialSms.length} financial SMS out of ${messages.length} total',
      );

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
      int skipped = 0;

      final dio = Dio(
        BaseOptions(
          baseUrl: AppEnv.apiBaseUrl,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      for (final msg in financialSms) {
        try {
          // Check if SMS was already processed by calling the API
          final body = msg.body ?? '';
          final sender = msg.sender ?? '';
          
          // Create a hash of the SMS body to check for duplicates
          final smsHash = _hashSms(body);
          
          // First check if this SMS was already processed
          try {
            final checkResponse = await dio.post(
              '/v1/sms/check-duplicate',
              data: {
                'body_hash': smsHash,
                'sender': sender,
              },
            );
            
            if (checkResponse.data['exists'] == true) {
              skipped++;
              smsScanLog('SMS already processed, skipping');
              continue;
            }
          } on DioException catch (e) {
            // If check fails, proceed with submission (fallback)
            smsScanLog('Duplicate check failed, proceeding: ${e.message}');
          }

          await dio.post(
            '/v1/sms',
            data: {
              'body': body,
              if (sender.isNotEmpty) 'sender': sender,
            },
          );
          processed++;
          smsScanLog('Processed SMS from $sender');
        } on DioException catch (e) {
          failed++;
          smsScanLog(
            'Failed to process SMS: ${e.response?.statusCode} ${e.message}',
          );
        } catch (e) {
          failed++;
          smsScanLog('Error processing SMS: $e');
        }
      }

      smsScanLog('Scan complete: $processed processed, $failed failed, $skipped skipped');
      return ScanResult.success(processed, failed, 'Scan completed', skipped);
    } catch (e) {
      smsScanLog('Scan failed: $e');
      return ScanResult.error('Scan failed: $e');
    }
  }

  /// Create a simple hash of SMS body for duplicate checking
  String _hashSms(String body) {
    // Simple hash based on content length and first/last characters
    final normalized = body.trim().toLowerCase();
    if (normalized.length < 10) return normalized;
    return '${normalized.length}_${normalized.substring(0, 5)}_${normalized.substring(normalized.length - 5)}';
  }

  /// Check if SMS body appears to be financial
  bool _isFinancialSms(String body) {
    final b = body.toLowerCase();
    const keywords = [
      'mwk',
      'kwacha',
      'airtel',
      'mpamba',
      'tnm',
      'mo626',
      'received',
      'sent',
      'withdrawn',
      'deposited',
      'payment',
      'balance',
      'transaction',
      'national bank',
      'standard bank',
      'fdh',
      'nbs',
      'paid',
      'debited',
      'credited',
    ];
    return keywords.any(b.contains);
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

extension on SmsMessage {
  String get sender => address ?? '';
}
