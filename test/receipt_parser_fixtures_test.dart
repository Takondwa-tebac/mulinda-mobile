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
/// Two groups, scored apart so a batch of harder receipts can't hide a
/// regression on the easy ones:
/// - screens: app screenshots and clear scans (the first 54 fixtures). Parser
///   v1 scored 100% on every field except reference (47/48).
/// - photos: phone photos of paper slips (`photo_*`, added with parser v2):
///   faded thermal print, stamps, tilt and blur. Their minimums start at what
///   v2 scored.
/// Whatever the minimums, a wrong amount must never be trusted.
const _minimumAccuracy = {
  'screens': {
    'kind': 0.95,
    'amount': 0.95,
    'fee': 0.95,
    'merchant': 0.90,
    'payee': 0.90,
    'reference': 0.90,
    'date': 0.95,
    'fallback': 0.95,
  },
  'photos': {
    'kind': 0.85,
    'amount': 0.85,
    'fee': 0.95,
    'merchant': 0.90,
    'payee': 0.90,
    'reference': 0.15,
    'date': 0.55,
    'fallback': 0.85,
  },
};

String _group(String id) => id.startsWith('photo_') ? 'photos' : 'screens';

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
  final scores = {
    for (final MapEntry(key: group, value: fields) in _minimumAccuracy.entries)
      group: {for (final f in fields.keys) f: _Score()},
  };
  final confidentlyWrong = <String>[];

  for (final MapEntry(key: id, value: raw) in answers.entries) {
    final expected = (raw as Map).cast<String, dynamic>();
    final doc = OcrDocument.fromJson(
      (jsonDecode(File('${_dir.path}/$id.ocr.json').readAsStringSync()) as Map).cast<String, dynamic>(),
    );
    final draft = _parser.parse(doc);
    final score = scores[_group(id)]!;
    final fallback = expected['expect_fallback'] as bool;
    final isReceipt = expected['is_receipt'] as bool;

    score['fallback']!.check(id, fallback ? 'fallback' : 'trusted', draft.needsFallback ? 'fallback' : 'trusted',
        draft.needsFallback == fallback);
    if (!isReceipt) {
      score['kind']!.check(id, 'not a payment', draft.kind.name, !draft.isReceipt);
      continue;
    }
    if (fallback) continue; // handwritten: only routing to the fallback matters

    score['kind']!.check(id, expected['kind'], draft.kind.name, _kindName(draft.kind) == expected['kind']);
    final amount = (expected['amount'] as num?)?.toDouble();
    final amountRight = draft.amount != null && amount != null && (draft.amount! - amount).abs() < 0.005;
    score['amount']!.check(id, amount, draft.amount, amountRight);
    if (!amountRight && !draft.needsFallback) confidentlyWrong.add('$id: expected $amount, got ${draft.amount}');

    if (expected['fee'] != null && expected['kind'] == 'bank_transfer') {
      final fee = (expected['fee'] as num).toDouble();
      score['fee']!.check(id, fee, draft.fee, (draft.fee ?? 0) == fee);
    }
    if (expected['merchant'] != null) {
      score['merchant']!.check(id, expected['merchant'], draft.merchant,
          draft.merchant != null && squash(draft.merchant!) == squash(expected['merchant'] as String));
    }
    if (expected['payee'] != null) {
      score['payee']!.check(id, expected['payee'], draft.payee,
          draft.payee != null && squash(draft.payee!) == squash(expected['payee'] as String));
    }
    if (expected['reference'] != null) {
      score['reference']!.check(id, expected['reference'], draft.reference,
          draft.reference != null && squash(draft.reference!) == squash(expected['reference'] as String));
    }
    if (expected['date'] != null) {
      final date = draft.occurredAt?.toIso8601String().substring(0, 10);
      score['date']!.check(id, expected['date'], date, date == expected['date']);
    }
  }

  // ignore: avoid_print
  print([
    'Receipt parser v${ReceiptParser.version} on ${answers.length} fixtures:',
    for (final MapEntry(key: group, value: fields) in scores.entries) ...[
      ' $group:',
      for (final MapEntry(key: field, value: s) in fields.entries) ...[
        '  ${field.padRight(10)} ${(s.accuracy * 100).toStringAsFixed(1).padLeft(5)}%  (${s.right}/${s.total})',
        for (final m in s.misses) '      - $m',
      ],
    ],
  ].join('\n'));

  for (final MapEntry(key: group, value: fields) in _minimumAccuracy.entries) {
    for (final MapEntry(key: field, value: minimum) in fields.entries) {
      final s = scores[group]![field]!;
      test('$group: $field accuracy stays at or above ${(minimum * 100).toStringAsFixed(0)}%', () {
        expect(s.accuracy, greaterThanOrEqualTo(minimum), reason: s.misses.join('\n'));
      });
    }
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
      ReceiptKind.cardSlip => 'card_slip',
      ReceiptKind.notPayment => 'not_payment',
      ReceiptKind.unknown => 'unknown',
    };
