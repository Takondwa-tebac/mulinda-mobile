// Turns raw OCR exports from the debug "Receipt OCR" screen into redacted
// receipt parser fixtures.
//
//   dart run tool/receipt_fixtures.dart --names <names.txt> --out <dir> \
//       <id>=<raw.ocr.json> [<id>=<raw.ocr.json> ...]
//
// Redaction (the raw exports hold real names, accounts and phone numbers, and
// must never be committed):
// - every word listed in the names file (one name per line, any case) becomes
//   a stable pseudonym, so the same person maps to the same stand-in;
// - standalone digit runs of 7+ (accounts, phones, card and transaction
//   numbers) are replaced digit-for-digit with stable fake digits; lines that
//   carry a business TIN/TPIN/VAT number keep theirs, as the parser uses them;
// - e-mail addresses become redacted@example.com;
// - the free-text note beside a "Payment Details" label becomes "Payment note".
import 'dart:convert';
import 'dart:io';

import 'src/redactor.dart';

void main(List<String> args) {
  String? namesPath;
  String? outDir;
  final inputs = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--names':
        namesPath = args[++i];
      case '--out':
        outDir = args[++i];
      default:
        final eq = args[i].indexOf('=');
        if (eq < 1) _fail('Expected <id>=<raw.ocr.json>, got "${args[i]}"');
        inputs[args[i].substring(0, eq)] = args[i].substring(eq + 1);
    }
  }
  if (namesPath == null || outDir == null || inputs.isEmpty) {
    _fail('Usage: --names <names.txt> --out <dir> <id>=<raw.ocr.json> ...');
  }

  final redactor = Redactor(
    File(namesPath).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty),
  );
  Directory(outDir).createSync(recursive: true);

  for (final MapEntry(key: id, value: path) in inputs.entries) {
    final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final fixture = redactor.redactDocument(raw);
    File('$outDir/$id.ocr.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(fixture)}\n');
    stdout.writeln('$id <- $path');
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
