// Redaction shared by the receipt fixture tools (see receipt_fixtures.dart
// for the rules). Raw OCR holds real names, accounts and phone numbers.

const _pseudonyms = [
  'Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel',
  'India', 'Juliet', 'Kilo', 'Lima', 'Mike', 'November', 'Oscar', 'Papa',
  'Quebec', 'Romeo', 'Sierra', 'Tango', 'Uniform', 'Victor', 'Whiskey', 'Yankee',
];

class Redactor {
  Redactor(Iterable<String> names)
      : _names = {for (final n in names) for (final w in n.split(RegExp(r'\s+'))) w.toLowerCase()};

  final Set<String> _names;

  /// Apostrophes only inside a word, so a quoted 'Name' still matches.
  static final _word = RegExp(r"[A-Za-z](?:[A-Za-z'’]*[A-Za-z])?");
  static final _digitRun = RegExp(r'(?<![A-Za-z0-9])\d{7,}(?![A-Za-z0-9])');
  /// Any token with an "@" after a letter, so half-read addresses
  /// ("name@gma") go too; "3,995.00 @ 79.90" (a rate) does not match.
  static final _email = RegExp(r'[\w.+-]*[A-Za-z][\w.+-]*@[\w.-]*');
  /// "Payment Details: Tpt" read as one line.
  static final _inlineNote = RegExp(r'^(Payment Details\s*:)\s*\S.*$');
  /// Mask characters next to digits ("44**", "XXX*X1035"), or a "Card No" /
  /// "Account Number" label (account numbers can mix in letters:
  /// MWKLZ8079...). Also a card's last four alone on a line (":5423").
  static final _maskedCard = RegExp(
    r'\d[*X]{2,}|\d(\s*[*X]){3,}|([*X]\s*){3,}\d|C?ard\s*No|Account\s*Num|^\W{1,2}\d{4}$',
    caseSensitive: false,
  );
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
    if (_maskedCard.hasMatch(out)) {
      // A masked card number ("4500 44** **** 1035", "450044XXX*X1035"):
      // fake every digit on the line, as the BIN and last four survive OCR
      // in pieces too short for the digit-run rule.
      out = out.replaceAllMapped(RegExp(r'\d+'), (m) => _fakeDigits(m[0]!));
    } else if (!_businessId.hasMatch(out)) {
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
