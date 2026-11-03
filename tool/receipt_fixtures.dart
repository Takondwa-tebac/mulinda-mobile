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

const _pseudonyms = [
  'Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel',
  'India', 'Juliet', 'Kilo', 'Lima', 'Mike', 'November', 'Oscar', 'Papa',
  'Quebec', 'Romeo', 'Sierra', 'Tango', 'Uniform', 'Victor', 'Whiskey', 'Yankee',
];

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

class Redactor {
  Redactor(Iterable<String> names)
      : _names = {for (final n in names) for (final w in n.split(RegExp(r'\s+'))) w.toLowerCase()};

  final Set<String> _names;

  static final _word = RegExp(r"[A-Za-z][A-Za-z'’]*");
  static final _digitRun = RegExp(r'(?<![A-Za-z0-9])\d{7,}(?![A-Za-z0-9])');
  /// Any token with an "@" after a letter, so half-read addresses
  /// ("name@gma") go too; "3,995.00 @ 79.90" (a rate) does not match.
  static final _email = RegExp(r'[\w.+-]*[A-Za-z][\w.+-]*@[\w.-]*');
  /// "Payment Details: Tpt" read as one line.
  static final _inlineNote = RegExp(r'^(Payment Details\s*:)\s*\S.*$');
  static final _businessId =RegExp(r'\b(T?PIN|TIN|VAT\s*#?)\b', caseSensitive: false);

  Map<String, dynamic> redactDocument(Map<String, dynamic> doc) {
    final lines = (doc['lines'] as List).cast<Map<String, dynamic>>();
    final notes = _noteLineIndexes(lines);
    return {
      'engine': doc['engine'],
      'lines': [
        for (final (i, line) in lines.indexed)
          {
            'text': notes.contains(i)
                ? 'Payment note'
                : redactText((line['text'] as String).replaceFirstMapped(_inlineNote, (m) => '${m[1]} Payment note')),
            'box': line['box'],
            'block': line['block'],
          },
      ],
    };
  }

  String redactText(String text) {
    var out = text.replaceAll(_email, 'redacted@example.com');
    if (!_businessId.hasMatch(out)) {
      out = out.replaceAllMapped(_digitRun, (m) => _fakeDigits(m[0]!));
    }
    return out.replaceAllMapped(_word, (m) {
      final word = m[0]!;
      if (!_names.contains(word.toLowerCase())) return word;
      final stand = _pseudonyms[_hash(word.toLowerCase()) % _pseudonyms.length];
      return word == word.toUpperCase() ? stand.toUpperCase() : stand;
    });
  }

  /// Lines right of a "Payment Details" label on the same row.
  Set<int> _noteLineIndexes(List<Map<String, dynamic>> lines) {
    List<double> box(Map<String, dynamic> l) => (l['box'] as List).map((v) => (v as num).toDouble()).toList();
    final result = <int>{};
    for (final label in lines.where((l) => RegExp(r'^Payment Details:?$').hasMatch((l['text'] as String).trim()))) {
      final lb = box(label);
      final cy = (lb[1] + lb[3]) / 2;
      for (final (i, line) in lines.indexed) {
        final b = box(line);
        if (b[0] > lb[2] && ((b[1] + b[3]) / 2 - cy).abs() < (lb[3] - lb[1])) result.add(i);
      }
    }
    return result;
  }

  String _fakeDigits(String digits) {
    final seed = _hash(digits);
    return String.fromCharCodes([
      for (var i = 0; i < digits.length; i++) 0x30 + ((seed >> (i % 28)) + i * 7) % 10,
    ]);
  }

  /// FNV-1a, so pseudonyms and fake digits are stable across runs.
  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}
