import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_ocr.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_parser.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_text.dart';

/// Accuracy of the receipt parser on real (redacted) receipts.
///
/// Fixtures live in test/fixtures/receipts: `<id>.ocr.json` is ML Kit's output
/// for one photo (see tool/receipt_fixtures.dart), and answers.json holds what
/// the receipt really says. The minimums below only ever go up: raise them
/// when the parser improves, never lower them to make a change pass.
///
/// Parser v1 scored 100% on every field except reference (47/48) on the first
/// 54 fixtures; the minimums leave a little room for harder receipts added
/// later. Whatever the minimums, a wrong amount must never be trusted.
const _minimumAccuracy = {
  'kind': 0.95,
  'amount': 0.95,
  'fee': 0.95,
  'merchant': 0.90,
  'reference': 0.90,
  'date': 0.95,
  'fallback': 0.95,
};

final _dir = Directory('test/fixtures/receipts');
final _parser = ReceiptParser(now: DateTime(2026, 10, 31));

class _Score {
  int right = 0;
  int total = 0;
  final misses = <String>[];

  double get accuracy => total == 0 ? 1 : right / total;

  void check(String id, Object? expected, Object? actual, bool ok) {
    total++;
    if (ok) {
      right++;
    } else {
      misses.add('$id: expected $expected, got $actual');
    }
  }
}

void main() {
  final answers = (jsonDecode(File('${_dir.path}/answers.json').readAsStringSync()) as Map).cast<String, dynamic>();
  final scores = {for (final f in _minimumAccuracy.keys) f: _Score()};
  final confidentlyWrong = <String>[];

  for (final MapEntry(key: id, value: raw) in answers.entries) {
    final expected = (raw as Map).cast<String, dynamic>();
    final doc = OcrDocument.fromJson(
      (jsonDecode(File('${_dir.path}/$id.ocr.json').readAsStringSync()) as Map).cast<String, dynamic>(),
    );
    final draft = _parser.parse(doc);
    final fallback = expected['expect_fallback'] as bool;
    final isReceipt = expected['is_receipt'] as bool;

    scores['fallback']!.check(id, fallback ? 'fallback' : 'trusted', draft.needsFallback ? 'fallback' : 'trusted',
        draft.needsFallback == fallback);
    if (!isReceipt) {
      scores['kind']!.check(id, 'not a payment', draft.kind.name, !draft.isReceipt);
      continue;
    }
    if (fallback) continue; // handwritten: only routing to the fallback matters

    scores['kind']!.check(id, expected['kind'], draft.kind.name, _kindName(draft.kind) == expected['kind']);
    final amount = (expected['amount'] as num?)?.toDouble();
    final amountRight = draft.amount != null && amount != null && (draft.amount! - amount).abs() < 0.005;
    scores['amount']!.check(id, amount, draft.amount, amountRight);
    if (!amountRight && !draft.needsFallback) confidentlyWrong.add('$id: expected $amount, got ${draft.amount}');

    if (expected['fee'] != null && expected['kind'] == 'bank_transfer') {
      final fee = (expected['fee'] as num).toDouble();
      scores['fee']!.check(id, fee, draft.fee, (draft.fee ?? 0) == fee);
    }
    if (expected['merchant'] != null) {
      scores['merchant']!.check(id, expected['merchant'], draft.merchant,
          draft.merchant != null && squash(draft.merchant!) == squash(expected['merchant'] as String));
    }
    if (expected['reference'] != null) {
      scores['reference']!.check(id, expected['reference'], draft.reference,
          draft.reference != null && squash(draft.reference!) == squash(expected['reference'] as String));
    }
    if (expected['date'] != null) {
      final date = draft.occurredAt?.toIso8601String().substring(0, 10);
      scores['date']!.check(id, expected['date'], date, date == expected['date']);
    }
  }

  // ignore: avoid_print
  print([
    'Receipt parser v${ReceiptParser.version} on ${answers.length} fixtures:',
    for (final MapEntry(key: field, value: s) in scores.entries) ...[
      '  ${field.padRight(10)} ${(s.accuracy * 100).toStringAsFixed(1).padLeft(5)}%  (${s.right}/${s.total})',
      for (final m in s.misses) '      - $m',
    ],
  ].join('\n'));

  for (final MapEntry(key: field, value: minimum) in _minimumAccuracy.entries) {
    test('$field accuracy stays at or above ${(minimum * 100).toStringAsFixed(0)}%', () {
      expect(scores[field]!.accuracy, greaterThanOrEqualTo(minimum), reason: scores[field]!.misses.join('\n'));
    });
  }

  test('a wrong amount is never trusted (it must go to the fallback)', () {
    expect(confidentlyWrong, isEmpty);
  });
}

String _kindName(ReceiptKind kind) => switch (kind) {
      ReceiptKind.tillReceipt => 'till_receipt',
      ReceiptKind.bankTransfer => 'bank_transfer',
      ReceiptKind.mobileMoney => 'mobile_money',
      ReceiptKind.atmSlip => 'atm_slip',
      ReceiptKind.notPayment => 'not_payment',
      ReceiptKind.unknown => 'unknown',
    };
