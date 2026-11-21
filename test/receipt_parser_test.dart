import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_ocr.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_parser.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_text.dart';

/// Builds a document from rows of (left text, right text), one row per 50px.
OcrDocument _doc(List<(String, String?)> rows) => OcrDocument(lines: [
      for (final (i, (label, value)) in rows.indexed) ...[
        OcrLine(text: label, left: 40, top: i * 50.0, right: 300, bottom: i * 50.0 + 36, block: i),
        if (value != null) OcrLine(text: value, left: 600, top: i * 50.0, right: 900, bottom: i * 50.0 + 36, block: 100 + i),
      ],
    ]);

void main() {
  group('parseAmountLine', () {
    test('reads amounts the way receipts and OCR print them', () {
      expect(parseAmountLine('MWK 10,000.00'), 10000);
      expect(parseAmountLine('33,968. 00'), 33968);
      expect(parseAmountLine('5,000, 00'), 5000);
      expect(parseAmountLine('8.245.88 A'), 8245.88);
      expect(parseAmountLine('K23500.0'), 23500);
      expect(parseAmountLine('MWK19627.36'), 19627.36);
      expect(parseAmountLine(': MWK 100,000.00'), 100000);
      expect(parseAmountLine('MK 18,800'), 18800);
      expect(parseAmountLine('1,700.00'), 1700);
    });

    test('refuses phone numbers, IDs, quantities and garbled text', () {
      expect(parseAmountLine('0999588666'), isNull);
      expect(parseAmountLine('08428'), isNull);
      expect(parseAmountLine('2'), isNull);
      expect(parseAmountLine('1,BGG,GU0.BS'), isNull);
      expect(parseAmountLine('TOTAL Sbs. sooUD'), isNull);
      expect(parseAmountLine('FT262805KGC1'), isNull);
      expect(parseAmountLine(''), isNull);
    });
  });

  group('parseDate', () {
    final now = DateTime(2026, 10, 31);

    test('reads the date formats seen on Malawian receipts', () {
      expect(parseDate('2026-10-26 16:51:58', now: now), DateTime(2026, 10, 26, 16, 51, 58));
      expect(parseDate('07-0ct-2026 19:00:57', now: now), DateTime(2026, 10, 7, 19, 0, 57));
      expect(parseDate('30 Jul 2026, 06:49', now: now), DateTime(2026, 7, 30, 6, 49));
      expect(parseDate('Date & Time 26/10/2026 09:17', now: now), DateTime(2026, 10, 26, 9, 17));
      expect(parseDate('10/10/ 26 17;42 70518045', now: now), DateTime(2026, 10, 10, 17, 42));
      expect(parseDate('21 Septenber 2026 19:10:43', now: now), DateTime(2026, 9, 21, 19, 10, 43));
      expect(parseDate('12:25 PM', now: now), isNull);
    });

    test('repairs dot-matrix 8s read in place of 0s', () {
      expect(parseDate('DATE 2826-18-19', now: now), DateTime(2026, 10, 19));
    });

    test('rejects impossible dates', () {
      expect(parseDate('31/02/2026', now: now), isNull);
      expect(parseDate('2031-01-01', now: now), isNull);
      expect(parseDate('Doc ID: 22253625', now: now), isNull);
    });
  });

  group('ReceiptParser', () {
    final parser = ReceiptParser(now: DateTime(2026, 10, 31));

    test('an empty read goes to the fallback', () {
      final draft = parser.parse(const OcrDocument(lines: []));
      expect(draft.amount, isNull);
      expect(draft.needsFallback, isTrue);
    });

    test('a till receipt pairs TOTAL with its amount, not the cash or change', () {
      final draft = parser.parse(_doc([
        ('*** START OF LEGAL RECEIPT ***', null),
        ('TIN: 31617337', null),
        ('Subtotal', '17,872.34'),
        ('VAT A - 17.5%', '3,127.66'),
        ('TOTAL', '21,000.00'),
        ('Amount Paid', '25,000.00'),
        ('Change', '4,000.00'),
        ('Date', '2026-10-26 16:51:58'),
      ]));

      expect(draft.kind, ReceiptKind.tillReceipt);
      expect(draft.amount, 21000);
      expect(draft.merchant, 'Lucky Shopping Center');
      expect(draft.occurredAt, DateTime(2026, 10, 26, 16, 51, 58));
      expect(draft.needsFallback, isFalse);
    });

    test('values printed a row above their labels are still paired correctly', () {
      final draft = parser.parse(OcrDocument(lines: [
        const OcrLine(text: 'START OF LEGAL RECEIPT', left: 300, top: 0, right: 900, bottom: 36, block: 0),
        for (final (i, (label, value)) in [
          ('TAXABLE A-17.5%', '28,908.94'),
          ('VAT A-17.5%', '5,059.06'),
          ('TOTAL VAT', '5,059.06'),
          ('TOTAL', '33,968.00'),
          ('CASH', '35,000.00'),
          ('CHANGE', '1,032.00'),
        ].indexed) ...[
          OcrLine(text: label, left: 40, top: 200 + i * 47.0, right: 300, bottom: 236 + i * 47.0, block: 1 + i),
          // Each value sits one row higher than its label.
          OcrLine(text: value, left: 800, top: 153 + i * 47.0, right: 1100, bottom: 189 + i * 47.0, block: 20 + i),
        ],
      ]));

      expect(draft.amount, 33968);
    });

    test('a pro-forma invoice is not a payment', () {
      final draft = parser.parse(_doc([('Amaryllis Hotel', null), ('Pre -Forma Invoice', null), ('Total Charges', '79000.00')]));
      expect(draft.isReceipt, isFalse);
      expect(draft.needsFallback, isFalse);
      expect(draft.toPayload()['is_receipt'], isFalse);
    });

    test('an unrecognised layout is never trusted, even with a total', () {
      final draft = parser.parse(_doc([('CASH RECEIPT', null), ('TOTAL', '5,000.00')]));
      expect(draft.kind, ReceiptKind.unknown);
      expect(draft.needsFallback, isTrue);
    });

    test('the payload matches the shape the API stores for AI scans', () {
      final payload = parser.parse(_doc([('TOTAL', '5,000.00')])).toPayload();
      expect(payload.keys, containsAll(['is_receipt', 'type', 'amount', 'currency', 'merchant', 'reference', 'occurred_at', 'confidence']));
      expect(payload['parser'], 'device');
      expect(payload['parser_version'], ReceiptParser.version);
    });
  });

  group('ReceiptParser v2 (photos of paper slips)', () {
    final parser = ReceiptParser(now: DateTime(2026, 10, 31));

    test('reads a card machine slip: the shop under the bank logo and its amount', () {
      final draft = parser.parse(_doc([
        ('Standard Bank', null),
        ('BUYMORE', null),
        ('PURCHASE', 'Date 02/06/2026'),
        ('Amount: MWK 22,600.00', null),
        ('Approved', null),
        ('CUSTOMER COPY', null),
      ]));

      expect(draft.kind, ReceiptKind.cardSlip);
      expect(draft.amount, 22600);
      expect(draft.merchant, 'Buy More');
      expect(draft.needsFallback, isFalse);
    });

    test('a declined card slip is not a payment', () {
      final draft = parser.parse(_doc([
        ('Standard Bank', null),
        ('BUYMORE', null),
        ('Amount: MWK 22,600.00', null),
        ('Declined', null),
        ('51- DO NOT HONOR', null),
      ]));

      expect(draft.kind, ReceiptKind.notPayment);
      expect(draft.isReceipt, isFalse);
    });

    test('a total nothing confirms is not trusted, however it was labelled', () {
      final draft = parser.parse(_doc([
        ('*** START OF LEGAL RECEIPT ***', null),
        ('TOTAL', '4,000.08'),
        ('DATE 2026-06-18', null),
      ]));

      expect(draft.amount, 4000.08);
      expect(draft.needsFallback, isTrue);
    });

    test('a missed TOTAL line is recovered from the VAT and the taxable amount', () {
      // The TOTAL value was not read; 30,638.30 + 5,361.70 = 36,000.00 and
      // 36,000 x 0.175 / 1.175 = 5,361.70 confirm the item line.
      final draft = parser.parse(_doc([
        ('*** START OF LEGAL RECEIPT ***', null),
        ('GOODS 1 X 36.000.00', null),
        ('TAXABLE A-17.5%', '30,638.30'),
        ('VAT A-17.5%', '5,361.70'),
        ('TOTAL', null),
        ('CHANGE', '4,000.08'),
      ]));

      expect(draft.amount, 36000);
    });

    test('a VAT-rated item is not taken for the total', () {
      final draft = parser.parse(_doc([
        ('*** START OF LEGAL RECEIPT ***', null),
        ('FRIED VEGETABLES', '291.60'),
        ('RICE', '1,932.00'),
        ('Sales VAT A', '43.43'),
        ('Sub Total', '248.17'),
        ('Tendered', '5,000.00'),
        ('Cash Balance', '2,776.40'),
        ('CASH', '2,223.60'),
      ]));

      expect(draft.amount, 2223.60);
    });

    test('0.00 lines confirm nothing and are never the total', () {
      final draft = parser.parse(_doc([
        ('*** START OF LEGAL RECEIPT ***', null),
        ('ITEM', '8,650.00A'),
        ('VAT B-0%:', '0.00'),
        ('TOTAL:', '0.00'),
        ('DATE: 2026-09-04', null),
      ]));

      expect(draft.amount, isNot(0));
      expect(draft.needsFallback, isTrue);
    });

    test('a very long receipt still parses quickly (entry-level phones)', () {
      // 400 item lines, each with its own amount: confirming the total pairs
      // amounts, which must stay bounded however long the receipt is.
      final rows = <(String, String?)>[
        ('*** START OF LEGAL RECEIPT ***', null),
        for (var i = 1; i <= 400; i++) ('ITEM $i', '${(i * 137 % 9000) + 100}.${i % 100}'.padRight(6, '0')),
        ('TAXABLE A-17.5%', '30,638.30'),
        ('VAT A-17.5%', '5,361.70'),
        ('TOTAL', '36,000.00'),
      ];
      final parser = ReceiptParser(now: DateTime(2026, 10, 31));
      final doc = _doc(rows);
      parser.parse(doc); // warm up

      final watch = Stopwatch()..start();
      final draft = parser.parse(doc);
      watch.stop();

      expect(draft.amount, 36000);
      // ~10x headroom over a desktop run, so only a blow-up fails this.
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });
}
