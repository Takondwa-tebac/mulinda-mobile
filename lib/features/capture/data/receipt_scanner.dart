import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/activity_repository.dart';
import 'receipt_ocr.dart';
import 'receipt_parser.dart';

/// What the phone read from a receipt photo.
class DeviceReading {
  const DeviceReading({required this.document, required this.draft});

  final OcrDocument document;
  final ReceiptDraft draft;

  /// The server caps OCR uploads at 1000 lines of 500 characters.
  List<Map<String, dynamic>> get ocrLines => [
        for (final line in document.lines.take(1000))
          {
            ...line.toJson(),
            'text': line.text.length > 500 ? line.text.substring(0, 500) : line.text,
          },
      ];
}

/// The server's answer to an uploaded receipt.
enum ReceiptScanOutcome {
  /// Read and waiting in the inbox for approval.
  ready,

  /// Being read by the server's AI; it shows up in the inbox when done.
  pending,

  /// Not a payment receipt (a quotation, a job card, ...).
  notReceipt,
}

class ReceiptScanResult {
  const ReceiptScanResult({required this.outcome, this.scanId, this.duplicateTransactionId});

  final ReceiptScanOutcome outcome;
  final String? scanId;

  /// An existing transaction with the same reference: probably already recorded.
  final String? duplicateTransactionId;

  factory ReceiptScanResult.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString();
    return ReceiptScanResult(
      outcome: switch (status) {
        'parsed' => ReceiptScanOutcome.ready,
        'rejected' => ReceiptScanOutcome.notReceipt,
        _ => ReceiptScanOutcome.pending,
      },
      scanId: json['id']?.toString(),
      duplicateTransactionId: json['duplicate_transaction_id']?.toString(),
    );
  }
}

/// Reads a receipt on the phone, then uploads the photo with what was read.
///
/// The on-device reading is best effort: if ML Kit or the parser throws, the
/// photo is uploaded alone and the server reads it the old way.
class ReceiptScanner {
  ReceiptScanner({required this.ocr, required this.repository, this.parser = const ReceiptParser()});

  final ReceiptOcr ocr;
  final ActivityRepository repository;
  final ReceiptParser parser;

  Future<DeviceReading?> read(String imagePath) async {
    try {
      final document = await ocr.read(imagePath);
      return DeviceReading(document: document, draft: parser.parse(document));
    } catch (e, st) {
      debugPrint('receipt on-device read failed: $e\n$st');
      return null;
    }
  }

  /// [onDevice] off skips the phone reading (the kill switch).
  Future<ReceiptScanResult> scan(String imagePath, {required bool onDevice}) async {
    final reading = onDevice ? await read(imagePath) : null;
    return repository.scanReceipt(
      imagePath,
      clientId: newClientId(),
      draft: reading?.draft.toPayload(),
      ocrLines: reading?.ocrLines,
    );
  }

  /// Lets the server recognise a retried upload instead of storing it twice.
  static String newClientId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

final receiptScannerProvider = Provider<ReceiptScanner>((ref) => ReceiptScanner(
      ocr: ref.read(receiptOcrProvider),
      repository: ref.read(activityRepositoryProvider),
    ));
