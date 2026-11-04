import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_ocr.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_parser.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_scanner.dart';

/// Replays a stored OCR fixture, or fails like a broken ML Kit install.
class _FakeOcr implements ReceiptOcr {
  _FakeOcr(this.document);

  final OcrDocument? document;

  @override
  Future<OcrDocument> read(String imagePath, {String? source}) async =>
      document ?? (throw StateError('ML Kit unavailable'));

  @override
  Future<void> close() async {}
}

/// Records the upload instead of sending it.
class _RecordingRepository extends ActivityRepository {
  _RecordingRepository() : super(Dio());

  String? clientId;
  Map<String, dynamic>? draft;
  List<Map<String, dynamic>>? ocrLines;
  int uploads = 0;

  @override
  Future<ReceiptScanResult> scanReceipt(
    String filePath, {
    String? clientId,
    Map<String, dynamic>? draft,
    List<Map<String, dynamic>>? ocrLines,
  }) async {
    uploads++;
    this.clientId = clientId;
    this.draft = draft;
    this.ocrLines = ocrLines;
    return const ReceiptScanResult(outcome: ReceiptScanOutcome.ready);
  }
}

OcrDocument _fixture(String id) => OcrDocument.fromJson(
      jsonDecode(File('test/fixtures/receipts/$id.ocr.json').readAsStringSync()) as Map<String, dynamic>,
    );

void main() {
  final parser = ReceiptParser(now: DateTime(2026, 10, 31));

  test('uploads the photo with the draft and OCR lines read on the phone', () async {
    final repo = _RecordingRepository();
    final scanner = ReceiptScanner(ocr: _FakeOcr(_fixture('nbm_payment_01')), repository: repo, parser: parser);

    await scanner.scan('receipt.jpg', onDevice: true, clientId: 'client-1');

    expect(repo.draft, isNotNull);
    expect(repo.draft!['parser'], 'device');
    expect(repo.draft!['parser_version'], ReceiptParser.version);
    expect(repo.draft!['merchant'], 'National Bank of Malawi');
    expect(repo.ocrLines, isNotEmpty);
    expect(repo.ocrLines!.first.keys, containsAll(['text', 'box', 'block']));
    expect(repo.clientId, 'client-1');
  });

  test('the kill switch skips the phone and uploads the photo alone', () async {
    final repo = _RecordingRepository();
    final scanner = ReceiptScanner(ocr: _FakeOcr(_fixture('nbm_payment_01')), repository: repo, parser: parser);

    await scanner.scan('receipt.jpg', onDevice: false, clientId: 'client-1');

    expect(repo.uploads, 1);
    expect(repo.draft, isNull);
    expect(repo.ocrLines, isNull);
  });

  test('a failing OCR falls back to uploading the photo alone', () async {
    final repo = _RecordingRepository();
    final scanner = ReceiptScanner(ocr: _FakeOcr(null), repository: repo, parser: parser);

    await scanner.scan('receipt.jpg', onDevice: true, clientId: 'client-1');

    expect(repo.uploads, 1);
    expect(repo.draft, isNull);
  });

  test('OCR lines are capped to what the server accepts', () {
    final long = OcrLine(text: 'x' * 600, left: 0, top: 0, right: 1, bottom: 1, block: 0);
    final reading = DeviceReading(
      document: OcrDocument(lines: List.filled(1200, long)),
      draft: parser.parse(const OcrDocument(lines: [])),
    );

    expect(reading.ocrLines, hasLength(1000));
    expect(reading.ocrLines.first['text'], hasLength(500));
  });

  test('client ids are unique per image', () {
    expect(ReceiptScanner.newClientId(), hasLength(32));
    expect(ReceiptScanner.newClientId(), isNot(ReceiptScanner.newClientId()));
  });

  test('retrying an upload sends the same client id, so the server stores it once', () async {
    final repo = _RecordingRepository();
    final scanner = ReceiptScanner(ocr: _FakeOcr(_fixture('nbm_payment_01')), repository: repo, parser: parser);

    await scanner.scan('receipt.jpg', onDevice: true, clientId: 'client-1');
    final first = repo.clientId;
    await scanner.scan('receipt.jpg', onDevice: true, clientId: 'client-1');

    expect(repo.uploads, 2);
    expect(repo.clientId, first);
  });

  test('the parser runs on a background isolate and reads the same as on the main one', () async {
    final document = _fixture('efd_chipiku');
    final scanner = ReceiptScanner(ocr: _FakeOcr(document), repository: _RecordingRepository(), parser: parser);

    final reading = await scanner.read('receipt.jpg');

    expect(reading, isNotNull);
    expect(reading!.draft.toPayload(), parser.parse(document).toPayload());
    expect(reading.ocrLines, DeviceReading.linesFor(document));
  });

  test('the server response maps to an outcome', () {
    expect(ReceiptScanResult.fromJson({'status': 'parsed'}).outcome, ReceiptScanOutcome.ready);
    expect(ReceiptScanResult.fromJson({'status': 'pending'}).outcome, ReceiptScanOutcome.pending);
    expect(ReceiptScanResult.fromJson({'status': 'rejected'}).outcome, ReceiptScanOutcome.notReceipt);

    final duplicate = ReceiptScanResult.fromJson({
      'id': 'scan-1',
      'status': 'parsed',
      'duplicate_transaction_id': 'txn-9',
    });
    expect(duplicate.scanId, 'scan-1');
    expect(duplicate.duplicateTransactionId, 'txn-9');
  });
}
