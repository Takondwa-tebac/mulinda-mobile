// Turns a receipt-scan export from the API (app:export-receipt-scans
// --with-ocr) into redacted parser fixtures: the feedback loop.
//
//   dart run tool/import_receipt_export.dart --names <names.txt> \
//       [--out test/fixtures/receipts] <unzipped export dir> [<dir> ...]
//
// Each scan a user approved and that carries the phone's OCR text becomes
// `scan_<id>.ocr.json`, and its approved values (amount, fee, merchant, payee,
// reference, date) are added to answers.json as the expected answers, with
// `verified: false` until someone checks them against the photo. Names,
// account numbers and phones are redacted with the same stable rules as
// receipt_fixtures.dart, in the answers too, so they still match the text.
//
// Skipped: unapproved scans, scans without OCR, ids already in answers.json,
// and receipts whose redacted text is identical to an existing fixture (the
// same receipt scanned twice).
//
// Then run `flutter test test/receipt_parser_fixtures_test.dart`: its misses
// are what to tune. Bump ReceiptParser.version when the rules change.
import 'dart:convert';
import 'dart:io';

import 'src/redactor.dart';

void main(List<String> args) {
  String? namesPath;
  var outDir = 'test/fixtures/receipts';
  final exports = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--names':
        namesPath = args[++i];
      case '--out':
        outDir = args[++i];
      default:
        exports.add(args[i]);
    }
  }
  if (namesPath == null || exports.isEmpty) {
    _fail('Usage: --names <names.txt> [--out <dir>] <export dir> ...');
  }

  final redactor = Redactor(
    File(namesPath).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty),
  );
  final answersFile = File('$outDir/answers.json');
  final answers = (jsonDecode(answersFile.readAsStringSync()) as Map).cast<String, dynamic>();
  final knownTexts = {
    for (final f in Directory(outDir).listSync().whereType<File>().where((f) => f.path.endsWith('.ocr.json')))
      _text(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
  };
  // Two photos of one receipt read slightly differently, but share these.
  final knownReceipts = {
    for (final answer in answers.values) ?_receiptKey((answer as Map).cast<String, dynamic>()),
  };

  final skipped = <String, int>{};
  void skip(String why) => skipped[why] = (skipped[why] ?? 0) + 1;
  var added = 0;

  for (final dir in exports) {
    final csv = File('$dir/answers.csv');
    if (!csv.existsSync()) _fail('No answers.csv in $dir (unzip each export part into its own folder).');

    for (final row in readCsv(csv.readAsStringSync())) {
      if (row['verified'] != 'yes') {
        skip('not approved');
        continue;
      }
      final ocrFile = File('$dir/${row['ocr_file']}');
      if ((row['ocr_file'] ?? '').isEmpty || !ocrFile.existsSync()) {
        skip('no OCR');
        continue;
      }
      final id = 'scan_${row['scan_id']!.substring(0, 8)}';
      if (answers.containsKey(id)) {
        skip('already imported');
        continue;
      }
      final fixture = redactor.redactDocument(jsonDecode(ocrFile.readAsStringSync()) as Map<String, dynamic>);
      final answer = answerFor(row, redactor);
      final receipt = _receiptKey(answer);
      if (!knownTexts.add(_text(fixture)) || (receipt != null && !knownReceipts.add(receipt))) {
        skip('duplicate of an existing fixture');
        continue;
      }

      File('$outDir/$id.ocr.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(fixture)}\n');
      answers[id] = answer;
      added++;
      stdout.writeln('$id <- ${row['scan_id']}');
    }
  }

  final sorted = {for (final id in answers.keys.toList()..sort()) id: answers[id]};
  answersFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(sorted)}\n');
  stdout.writeln('Added $added fixture(s).');
  for (final MapEntry(key: why, value: n) in skipped.entries) {
    stdout.writeln('Skipped $n: $why');
  }
}

/// The expected answers for one approved scan: what the user saved, redacted.
Map<String, dynamic> answerFor(Map<String, String> row, Redactor redactor) {
  String? text(String column) {
    final value = row[column]?.trim() ?? '';
    return value.isEmpty ? null : redactor.redactText(value);
  }

  double? number(String column) => double.tryParse(row[column] ?? '');

  // Nothing the parser recognised (handwriting, an odd layout): the right
  // outcome is the fallback, until the parser learns that layout.
  final kind = _snake(row['device_kind'] ?? '');
  final unreadable = kind.isEmpty || kind == 'unknown';
  final deviceAmount = number('device_total');
  final amount = number('total');

  return {
    'kind': unreadable ? 'unknown' : kind,
    'is_receipt': true,
    'expect_fallback': unreadable,
    'type': row['type']?.isNotEmpty == true ? row['type'] : 'expense',
    'amount': amount,
    'fee': number('fee') ?? 0.0,
    'currency': row['currency']?.isNotEmpty == true ? row['currency'] : 'MWK',
    'merchant': text('merchant'),
    'payee': ?text('payee'),
    'reference': text('reference'),
    'date': row['date']?.isNotEmpty == true ? row['date'] : null,
    'verified': false,
    if (deviceAmount != null && amount != null && (deviceAmount - amount).abs() >= 0.005)
      'note': 'Parser v${row['parser_version']} read the amount as $deviceAmount.',
    'source': 'approved scan ${row['scan_id']}',
  };
}

/// RFC 4180 CSV (quoted fields, doubled quotes, newlines inside quotes) as
/// one map per row, keyed by the header.
List<Map<String, String>> readCsv(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (quoted) {
      if (c == '"' && i + 1 < source.length && source[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
  }
  if (rows.isEmpty) return const [];
  final header = rows.first;
  return [
    for (final r in rows.skip(1)) {for (final (i, name) in header.indexed) name: i < r.length ? r[i] : ''},
  ];
}

/// Reference and amount identify a receipt; null without a reference.
String? _receiptKey(Map<String, dynamic> answer) {
  final reference = answer['reference'];
  return reference == null ? null : '$reference|${answer['amount']}';
}

String _text(Map<String, dynamic> doc) =>
    (doc['lines'] as List).map((l) => (l as Map)['text']).join('\n');

/// The parser's enum names (bankTransfer) as the answers spell them (bank_transfer).
String _snake(String name) => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
