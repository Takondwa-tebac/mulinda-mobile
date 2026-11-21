import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

/// A parser bug, thrown inside the background isolate.
class _BrokenParser extends ReceiptParser {
  const _BrokenParser();

  @override
  ReceiptDraft parse(OcrDocument doc) => throw StateError('parser bug');
}

/// A parser that never returns: the isolate must be killed, not left running.
class _HangingParser extends ReceiptParser {
  const _HangingParser();

  @override
  ReceiptDraft parse(OcrDocument doc) {
    var spins = 0;
    while (true) {
      spins++;
      if (spins < 0) break;
    }
    return const ReceiptDraft(kind: ReceiptKind.unknown, confidence: 0);
  }
}

OcrDocument _fixture(String id) => OcrDocument.fromJson(
      jsonDecode(File('test/fixtures/receipts/$id.ocr.json').readAsStringSync()) as Map<String, dynamic>,
    );

void main() {
  final parser = ReceiptParser(now: DateTime(2026, 10, 31));

  test('reads a receipt on the phone: the draft, the upload-ready lines and the timings', () async {
    final scanner = ReceiptScanner(ocr: _FakeOcr(_fixture('nbm_payment_01')), parser: parser);

    final reading = await scanner.read('receipt.jpg');

    expect(reading, isNotNull);
    expect(reading!.draft.merchant, 'National Bank of Malawi');
    expect(reading.draft.toPayload()['parser_version'], ReceiptParser.version);
    expect(reading.ocrLines.first.keys, containsAll(['text', 'box', 'block']));
    expect(reading.ocrMs, isNotNull);
    expect(reading.parseMs, isNotNull);
  });

  test('the background isolate reads exactly what the main isolate would', () async {
    final document = _fixture('efd_chipiku');
    final scanner = ReceiptScanner(ocr: _FakeOcr(document), parser: parser);

    final reading = await scanner.read('receipt.jpg');

    expect(reading!.draft.toPayload(), parser.parse(document).toPayload());
    expect(reading.ocrLines, DeviceReading.linesFor(document));
  });

  test('a failing OCR gives no reading, so the photo is uploaded alone', () async {
    final scanner = ReceiptScanner(ocr: _FakeOcr(null), parser: parser);

    expect(await scanner.read('receipt.jpg'), isNull);
  });

  test('a parser crash in the background isolate gives no reading, not an app crash', () async {
    final scanner = ReceiptScanner(ocr: _FakeOcr(_fixture('nbm_payment_01')), parser: const _BrokenParser());

    expect(await scanner.read('receipt.jpg'), isNull);
  });

  test('a parse that never ends is killed at the timeout', () async {
    // Were the isolate left spinning, this test run would never finish.
    final scanner = ReceiptScanner(
      ocr: _FakeOcr(_fixture('nbm_payment_01')),
      parser: const _HangingParser(),
      parseTimeout: const Duration(milliseconds: 300),
    );

    final watch = Stopwatch()..start();
    expect(await scanner.read('receipt.jpg'), isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('only the first 1000 OCR lines are parsed and uploaded', () async {
    const line = OcrLine(text: 'x', left: 0, top: 0, right: 1, bottom: 1, block: 0);
    final scanner = ReceiptScanner(ocr: _FakeOcr(OcrDocument(lines: List.filled(1500, line))), parser: parser);

    final reading = await scanner.read('receipt.jpg');

    expect(reading!.document.lines, hasLength(DeviceReading.maxLines));
    expect(reading.ocrLines, hasLength(DeviceReading.maxLines));
  });

  test('uploaded OCR lines are capped to 500 characters', () {
    final long = OcrLine(text: 'x' * 600, left: 0, top: 0, right: 1, bottom: 1, block: 0);

    expect(DeviceReading.linesFor(OcrDocument(lines: [long])).single['text'], hasLength(500));
  });

  test('client ids are unique per image', () {
    expect(ReceiptScanner.newClientId(), hasLength(32));
    expect(ReceiptScanner.newClientId(), isNot(ReceiptScanner.newClientId()));
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
