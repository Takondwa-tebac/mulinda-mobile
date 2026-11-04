import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/activity_repository.dart';
import 'receipt_ocr.dart';
import 'receipt_parser.dart';

/// What the phone read from a receipt photo.
class DeviceReading {
  DeviceReading({required this.document, required this.draft, List<Map<String, dynamic>>? ocrLines})
      : ocrLines = ocrLines ?? linesFor(document);

  final OcrDocument document;
  final ReceiptDraft draft;

  /// The OCR lines as uploaded.
  final List<Map<String, dynamic>> ocrLines;

  /// The server caps OCR uploads at 1000 lines of 500 characters.
  static List<Map<String, dynamic>> linesFor(OcrDocument document) => [
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

  /// ML Kit already recognises text in native code, off the Dart thread. The
  /// parser is Dart, and on an entry-level phone a long receipt takes long
  /// enough to drop frames, so it runs on a background isolate; the UI keeps
  /// animating while it works.
  Future<DeviceReading?> read(String imagePath) async {
    try {
      final document = await ocr.read(imagePath);
      final parser = this.parser;
      final (draft, ocrLines) = await Isolate.run(() {
        final reading = DeviceReading(document: document, draft: parser.parse(document));
        return (reading.draft, reading.ocrLines);
      }, debugName: 'receipt-parser');
      return DeviceReading(document: document, draft: draft, ocrLines: ocrLines);
    } catch (e, st) {
      debugPrint('receipt on-device read failed: $e\n$st');
      return null;
    }
  }

  /// [onDevice] off skips the phone reading (the kill switch). [clientId]
  /// stays the same for every upload of one image, so a retry after a
  /// timeout returns the scan already stored instead of making a second one.
  Future<ReceiptScanResult> scan(String imagePath, {required bool onDevice, required String clientId}) async {
    final reading = onDevice ? await read(imagePath) : null;
    return repository.scanReceipt(
      imagePath,
      clientId: clientId,
      draft: reading?.draft.toPayload(),
      ocrLines: reading?.ocrLines,
    );
  }

  /// One per receipt image: lets the server recognise a retried upload.
  static String newClientId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

final receiptScannerProvider = Provider<ReceiptScanner>((ref) => ReceiptScanner(
      ocr: ref.read(receiptOcrProvider),
      repository: ref.read(activityRepositoryProvider),
    ));
