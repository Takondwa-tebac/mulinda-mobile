import 'package:flutter_test/flutter_test.dart';

import '../tool/import_receipt_export.dart';
import '../tool/src/redactor.dart';

void main() {
  test('reads quoted CSV fields, doubled quotes and newlines inside quotes', () {
    final rows = readCsv('scan_id,merchant,note\r\n'
        'a1,"Shoprite, Lilongwe","said ""hi""\nthen left"\r\n'
        'b2,Chipiku,\n');

    expect(rows, hasLength(2));
    expect(rows[0], {'scan_id': 'a1', 'merchant': 'Shoprite, Lilongwe', 'note': 'said "hi"\nthen left'});
    expect(rows[1]['merchant'], 'Chipiku');
    expect(rows[1]['note'], '');
  });

  final redactor = Redactor(['Robson Twea']);
  Map<String, String> row(Map<String, String> values) => {
        'scan_id': '9f1c2d3e-0000-0000-0000-000000000000',
        'verified': 'yes',
        'total': '10000',
        'currency': 'MWK',
        'merchant': 'National Bank of Malawi',
        'reference': 'FT262805KGC1',
        'date': '2026-10-07',
        'type': 'expense',
        'parser_version': '1',
        'payee': 'Robson Twea',
        'fee': '840',
        'device_kind': 'bankTransfer',
        'device_total': '10000',
        ...values,
      };

  test('an approved scan becomes expected answers, redacted like the OCR text', () {
    final answer = answerFor(row({}), redactor);

    expect(answer['kind'], 'bank_transfer');
    expect(answer['expect_fallback'], isFalse);
    expect(answer['amount'], 10000.0);
    expect(answer['fee'], 840.0);
    expect(answer['merchant'], 'National Bank of Malawi');
    expect(answer['payee'], redactor.redactText('Robson Twea'));
    expect(answer['payee'], isNot(contains('Robson')));
    expect(answer['reference'], 'FT262805KGC1');
    expect(answer['date'], '2026-10-07');
    expect(answer['verified'], isFalse);
    expect(answer.containsKey('note'), isFalse);
  });

  test('a corrected amount is noted, so the miss is easy to find', () {
    final answer = answerFor(row({'device_total': '1832.08', 'total': '33968'}), redactor);

    expect(answer['note'], 'Parser v1 read the amount as 1832.08.');
  });

  test('a receipt the parser could not place is expected to go to the fallback', () {
    final answer = answerFor(row({'device_kind': 'unknown'}), redactor);

    expect(answer['kind'], 'unknown');
    expect(answer['expect_fallback'], isTrue);
  });

  test('long digit runs in the reference are faked the same way as in the OCR text', () {
    final answer = answerFor(row({'reference': '1234567890'}), redactor);

    expect(answer['reference'], redactor.redactText('1234567890'));
    expect(answer['reference'], isNot('1234567890'));
  });
}
