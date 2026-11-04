import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'receipt_ocr.dart';
import 'receipt_parser.dart';

/// What the phone read from a receipt photo, and how long it took.
class DeviceReading {
  DeviceReading({
    required this.document,
    required this.draft,
    List<Map<String, dynamic>>? ocrLines,
    this.ocrMs,
    this.parseMs,
  }) : ocrLines = ocrLines ?? linesFor(document);

  final OcrDocument document;
  final ReceiptDraft draft;

  /// The OCR lines as uploaded.
  final List<Map<String, dynamic>> ocrLines;

  /// Time ML Kit took to read the image, and the parser to read the text.
  final int? ocrMs;
  final int? parseMs;

  /// The most lines read or uploaded: the server's cap, and far more than any
  /// receipt prints, so a pathological image can't make the parser run away.
  static const maxLines = 1000;

  /// The server caps OCR uploads at [maxLines] lines of 500 characters.
  static List<Map<String, dynamic>> linesFor(OcrDocument document) => [
        for (final line in document.lines.take(maxLines))
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

/// Reads a receipt on the phone: ML Kit's text recognition, then the parser.
///
/// The reading is best effort. Any failure (OCR, the isolate, the parser, or
/// a parse slower than [parseTimeout]) gives no reading, and the photo is
/// uploaded alone for the server to read the old way.
class ReceiptScanner {
  ReceiptScanner({required this.ocr, this.parser = const ReceiptParser(), this.parseTimeout = defaultParseTimeout});

  final ReceiptOcr ocr;
  final ReceiptParser parser;
  final Duration parseTimeout;

  /// Far beyond any real parse (~150 ms on an entry-level phone).
  static const defaultParseTimeout = Duration(seconds: 10);

  /// ML Kit recognises text in native code, off the Dart thread. The parser
  /// is Dart, and on an entry-level phone a long receipt takes long enough to
  /// drop frames, so it runs on a background isolate.
  Future<DeviceReading?> read(String imagePath) async {
    try {
      final ocrWatch = Stopwatch()..start();
      final read = await ocr.read(imagePath);
      ocrWatch.stop();
      final document = read.lines.length <= DeviceReading.maxLines
          ? read
          : OcrDocument(lines: read.lines.take(DeviceReading.maxLines).toList(), engine: read.engine, source: read.source);

      final parseWatch = Stopwatch()..start();
      final (draft, ocrLines) = await parseInBackground(parser, document, timeout: parseTimeout);
      parseWatch.stop();
      return DeviceReading(
        document: document,
        draft: draft,
        ocrLines: ocrLines,
        ocrMs: ocrWatch.elapsedMilliseconds,
        parseMs: parseWatch.elapsedMilliseconds,
      );
    } catch (e, st) {
      debugPrint('receipt on-device read failed: $e\n$st');
      return null;
    }
  }

  /// Parses on a background isolate that is killed if it overruns [timeout],
  /// so a runaway parse can't keep a CPU core (and memory) busy unseen.
  ///
  /// `Isolate.run` can't be cancelled, so this spawns the isolate itself. It
  /// is static and is sent only the parser and the OCR text: a closure inside
  /// an instance method could capture `this`. The port is always closed and
  /// the isolate always ends: it exits after sending its result, dies on an
  /// uncaught error (errors are fatal), or is killed on timeout.
  @visibleForTesting
  static Future<(ReceiptDraft, List<Map<String, dynamic>>)> parseInBackground(
    ReceiptParser parser,
    OcrDocument document, {
    required Duration timeout,
  }) async {
    final done = Completer<(ReceiptDraft, List<Map<String, dynamic>>)>();
    final port = RawReceivePort();
    Isolate? isolate;
    Timer? timer;

    void finish([Object? error]) {
      timer?.cancel();
      port.close();
      if (done.isCompleted) return;
      done.completeError(error ?? StateError('receipt parser isolate ended without a result'));
    }

    port.handler = (Object? message) {
      switch (message) {
        case (ReceiptDraft draft, List<Map<String, dynamic>> lines):
          timer?.cancel();
          port.close();
          if (!done.isCompleted) done.complete((draft, lines));
        case [final error, final stack]:
          finish(RemoteError('$error', '$stack'));
        default: // onExit (null) without a result
          finish();
      }
    };

    try {
      isolate = await Isolate.spawn(
        _parseEntry,
        (port.sendPort, parser, document),
        errorsAreFatal: true,
        onError: port.sendPort,
        onExit: port.sendPort,
        debugName: 'receipt-parser',
      );
    } catch (e) {
      finish(e);
      return done.future;
    }
    timer = Timer(timeout, () {
      isolate?.kill(priority: Isolate.immediate);
      finish(TimeoutException('receipt parse took longer than $timeout', timeout));
    });
    return done.future;
  }

  static void _parseEntry((SendPort, ReceiptParser, OcrDocument) message) {
    final (port, parser, document) = message;
    // exit() hands the result over without copying it, then ends the isolate.
    Isolate.exit(port, (parser.parse(document), DeviceReading.linesFor(document)));
  }

  /// One per receipt image: lets the server recognise a retried upload.
  static String newClientId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// The image's size in bytes, for the scan's timing report; null if unreadable.
int? imageBytes(String path) {
  try {
    return File(path).lengthSync();
  } catch (_) {
    return null;
  }
}

final receiptScannerProvider = Provider<ReceiptScanner>((ref) => ReceiptScanner(ocr: ref.read(receiptOcrProvider)));
