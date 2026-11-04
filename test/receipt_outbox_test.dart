import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_outbox.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_scanner.dart';

/// Answers uploads from a script: a result, or the HTTP status to fail with
/// (null status = no connection).
class _FakeUploader implements ReceiptUploader {
  final responses = <Object>[];
  final sent = <Map<String, dynamic>>[];

  @override
  Future<ReceiptScanResult> upload(File image, Map<String, dynamic> item) async {
    sent.add(item);
    final next = responses.isEmpty ? const ReceiptScanResult(outcome: ReceiptScanOutcome.ready) : responses.removeAt(0);
    if (next is ReceiptScanResult) return next;
    final options = RequestOptions(path: '/v1/receipt-scans');
    final (int? status, String? code) = next as (int?, String?);
    throw DioException(
      requestOptions: options,
      type: status == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response(requestOptions: options, statusCode: status, data: {'message': 'nope', 'code': ?code}),
    );
  }
}

void main() {
  late Directory root;
  late File image;
  late _FakeUploader uploader;
  late DateTime clock;
  late ReceiptOutbox outbox;

  setUp(() {
    root = Directory.systemTemp.createTempSync('receipt_outbox_test');
    image = File('${root.path}/scan.jpg')..writeAsBytesSync(List.filled(64, 1));
    uploader = _FakeUploader();
    clock = DateTime.now();
    outbox = ReceiptOutbox(uploader: uploader, root: () async => root, now: () => clock);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> queue(String id, {Map<String, dynamic>? draft}) async {
    expect(await outbox.enqueue(imagePath: image.path, clientId: id, draft: draft, metrics: {'ocr_ms': 812}), isTrue);
  }

  test('a queued receipt keeps its own copy of the image, so temporary files can go', () async {
    await queue('a');
    image.deleteSync();

    final upload = await outbox.send('a');

    expect(upload, isA<ReceiptUploaded>());
    expect(uploader.sent.single['client_id'], 'a');
    expect(uploader.sent.single['metrics'], {'ocr_ms': 812});
  });

  test('a sent receipt is deleted from the phone', () async {
    await queue('a');
    await outbox.send('a');

    expect(await outbox.pendingCount(), 0);
  });

  test('with no connection the receipt stays queued and is retried later', () async {
    await queue('a');
    uploader.responses.add((null, null));

    expect(await outbox.send('a'), isA<ReceiptQueued>());
    expect(await outbox.pendingCount(), 1);

    // Not due yet: the backoff holds it back.
    expect(await outbox.flush(), 0);
    clock = clock.add(const Duration(minutes: 1));
    expect(await outbox.flush(), 1);
    expect(await outbox.pendingCount(), 0);
    expect(uploader.sent.map((s) => s['client_id']), ['a', 'a']);
  });

  test('server trouble and throttling are retried; a refusal is final', () async {
    await queue('busy');
    uploader.responses.add((503, null));
    expect(await outbox.send('busy'), isA<ReceiptQueued>());

    await queue('throttled');
    uploader.responses.add((429, null));
    expect(await outbox.send('throttled'), isA<ReceiptQueued>());

    await queue('invalid');
    uploader.responses.add((422, null));
    final refused = await outbox.send('invalid');
    expect(refused, isA<ReceiptRejected>());
    expect((refused as ReceiptRejected).error.statusCode, 422);

    expect(await outbox.pendingCount(), 2);
  });

  test("the AI's spent quota is not retried: the user adds the receipt by hand", () async {
    await queue('a');
    uploader.responses.add((429, 'ai_rate_limited'));

    final upload = await outbox.send('a');

    expect(upload, isA<ReceiptRejected>());
    expect((upload as ReceiptRejected).error.code, 'ai_rate_limited');
    expect(await outbox.pendingCount(), 0);
  });

  test('a flush sends the oldest first and stops when the connection drops', () async {
    await queue('first');
    clock = clock.add(const Duration(seconds: 1));
    await queue('second');
    clock = clock.add(const Duration(seconds: 1));
    await queue('third');
    uploader.responses.addAll([const ReceiptScanResult(outcome: ReceiptScanOutcome.ready), (null, null)]);

    expect(await outbox.flush(), 1);
    expect(uploader.sent.map((s) => s['client_id']), ['first', 'second']);
    expect(await outbox.pendingCount(), 2);
  });

  test('queuing the same receipt twice keeps one', () async {
    await queue('a');
    await queue('a');

    expect(await outbox.pendingCount(), 1);
  });

  test('the queue is capped, so an offline phone does not fill its storage', () async {
    for (var i = 0; i < ReceiptOutbox.maxQueued; i++) {
      await queue('r$i');
    }

    expect(await outbox.enqueue(imagePath: image.path, clientId: 'one-more'), isFalse);
  });

  test('receipts that could not be sent for a month are dropped', () async {
    await queue('old');
    uploader.responses.add((null, null));
    await outbox.send('old');

    clock = clock.add(ReceiptOutbox.maxAge + const Duration(days: 1));
    await outbox.flush();

    expect(await outbox.pendingCount(), 0);
    expect(uploader.sent, hasLength(1));
  });

  test('a half-written item (the app died while queuing) is cleaned up', () async {
    final stray = Directory('${root.path}/receipt_outbox/broken')..createSync(recursive: true);
    File('${stray.path}/image.jpg').writeAsBytesSync([1]);

    clock = clock.add(const Duration(hours: 1));
    await outbox.flush();

    expect(stray.existsSync(), isFalse);
  });

  test('two senders never run at once (the app and the background worker)', () async {
    await queue('a');
    File('${root.path}/receipt_outbox/send.lock').writeAsStringSync('busy');

    expect(await outbox.send('a'), isA<ReceiptQueued>());
    expect(uploader.sent, isEmpty);
  });

  test('signing out clears every queued receipt', () async {
    await queue('a');
    await outbox.clear();

    expect(await outbox.pendingCount(), 0);
  });
}
