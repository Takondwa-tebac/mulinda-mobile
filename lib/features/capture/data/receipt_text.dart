import 'receipt_ocr.dart';

/// Reading money, dates and label/value pairs out of OCR text, tolerant of
/// the mistakes ML Kit makes on Malawian receipts: stray spaces inside numbers
/// ("33,968. 00"), "O" for "0" ("07-0ct-2026"), and 8s for 0s on dot-matrix
/// till printers ("DATE 2826-18-19").

final _currency = RegExp(r'^(MWK|MK|K)\.?\s*', caseSensitive: false);
final _number = RegExp(r'^\d{1,3}(?:[,.]\d{3})+(?:[.,]\d{1,2})?$|^\d+(?:[.,]\d{1,2})?$');

/// Parses a line that is nothing but an amount ("MWK 10,000.00",
/// "33,968. 00", "K23500.0", "21,000.00 A"). Returns null for anything else,
/// including bare whole numbers, which are far more often phone numbers, IDs
/// or quantities than money.
double? parseAmountLine(String text) {
  // A separator read into the value (": MWK 100,000.00").
  var s = text.trim().replaceFirst(RegExp(r'^[:;.\-\s]+'), '');
  // A trailing VAT class letter ("21,000.00 A").
  s = s.replaceFirst(RegExp(r'\s+[A-E]$'), '');
  final hasCurrency = _currency.hasMatch(s);
  s = s.replaceFirst(_currency, '');
  // "33,968. 00" / "5,000, 00" → no spaces around separators.
  s = s.replaceAllMapped(RegExp(r'\s*([,.])\s*'), (m) => m[1]!);
  if (!_number.hasMatch(s)) return null;

  final lastSep = s.lastIndexOf(RegExp(r'[,.]'));
  final hasDecimals = lastSep >= 0 && s.length - lastSep - 1 <= 2;
  final hasThousands = RegExp(r'\d[,.]\d{3}(?:[,.]|$)').hasMatch(s);
  if (!hasCurrency && !hasDecimals && !hasThousands) return null;

  final whole = (hasDecimals ? s.substring(0, lastSep) : s).replaceAll(RegExp(r'[,.]'), '');
  final fraction = hasDecimals ? s.substring(lastSep + 1) : '';
  return double.tryParse(fraction.isEmpty ? whole : '$whole.$fraction');
}

/// Finds an amount at the end of a line that also carries a label
/// ("Total:- MK 5,000.00", "TOTAL 33,968.00").
double? trailingAmount(String text) {
  final m = RegExp(r'((?:MWK|MK|K)?\.?\s*\d[\d,. ]*\d(?:\s*[A-E])?)$', caseSensitive: false).firstMatch(text.trim());
  return m == null ? null : parseAmountLine(m[1]!);
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses the first date in [text], day-first as printed in Malawi. Invalid
/// dates are repaired by turning OCR'd 8s back into 0s ("2826-18-19" →
/// 2026-10-19), and only dates from 2015 to next year are accepted.
DateTime? parseDate(String text, {DateTime? now}) {
  final maxYear = (now ?? DateTime.now()).year + 1;
  final s = text
      .replaceAllMapped(RegExp(r'\b0(ct|ec)\b', caseSensitive: false), (m) => 'O${m[1]}')
      .replaceAll(';', ':')
      .replaceAllMapped(RegExp(r'(\d)\s*([/-])\s*(\d)'), (m) => '${m[1]}${m[2]}${m[3]}');

  DateTime? build(String y, String mo, String d, int? month) {
    for (final yy in _repairs(y)) {
      for (final mm in month != null ? [mo] : _repairs(mo)) {
        for (final dd in _repairs(d)) {
          var year = int.parse(yy);
          if (yy.length == 2) year += 2000;
          final m = month ?? int.parse(mm);
          final day = int.parse(dd);
          if (year < 2015 || year > maxYear || m < 1 || m > 12 || day < 1 || day > 31) continue;
          final date = DateTime(year, m, day);
          if (date.month == m) return date; // rejects 31 Feb etc.
        }
      }
    }
    return null;
  }

  for (final m in RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').allMatches(s)) {
    final date = build(m[1]!, m[2]!, m[3]!, null);
    if (date != null) return _withTime(date, s.substring(m.end));
  }
  for (final m in RegExp(r'\b(\d{1,2})[\s-]+([A-Za-z]{3})[A-Za-z]*\.?[\s,-]+(\d{4})\b').allMatches(s)) {
    final month = _months[m[2]!.toLowerCase()];
    if (month == null) continue;
    final date = build(m[3]!, '$month', m[1]!, month);
    if (date != null) return _withTime(date, s.substring(m.end));
  }
  for (final m in RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})\b').allMatches(s)) {
    final date = build(m[3]!, m[2]!, m[1]!, null);
    if (date != null) return _withTime(date, s.substring(m.end));
  }
  return null;
}

/// The digit string as read, then with OCR'd 8s turned back into 0s.
Iterable<String> _repairs(String digits) sync* {
  yield digits;
  final eights = [for (var i = 0; i < digits.length; i++) if (digits[i] == '8') i];
  if (eights.isEmpty || eights.length > 4) return;
  for (var mask = 1; mask < 1 << eights.length; mask++) {
    final chars = digits.split('');
    for (var b = 0; b < eights.length; b++) {
      if (mask & (1 << b) != 0) chars[eights[b]] = '0';
    }
    yield chars.join();
  }
}

DateTime _withTime(DateTime date, String rest) {
  final t = RegExp(r'^[\s,T]*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?').firstMatch(rest);
  if (t == null) return date;
  var hour = int.parse(t[1]!);
  final pm = t[4]?.toLowerCase() == 'pm';
  if (pm && hour < 12) hour += 12;
  if (t[4]?.toLowerCase() == 'am' && hour == 12) hour = 0;
  final minute = int.parse(t[2]!);
  final second = int.parse(t[3] ?? '0');
  if (hour > 23 || minute > 59 || second > 59) return date;
  return DateTime(date.year, date.month, date.day, hour, minute, second);
}

/// Lowercase letters and digits only, for comparing names that OCR spaced or
/// punctuated differently.
String squash(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Geometry helpers for pairing labels with the values printed beside them.
extension ReceiptLayout on OcrDocument {
  double get width => lines.fold(0, (w, l) => l.right > w ? l.right : w);

  /// Typical line height, used as the unit for "same row" tolerances.
  double get lineHeight {
    if (lines.isEmpty) return 1;
    final heights = lines.map((l) => l.height).toList()..sort();
    return heights[heights.length ~/ 2];
  }

  /// Lines whose text starts with [label] (case-insensitive).
  Iterable<OcrLine> labelled(RegExp label) => lines.where((l) => label.hasMatch(l.text.trim()));

  /// The value for the first line matching [label]: printed after it on the
  /// same line ("Payment Own Ref : FT26…"), or the nearest line to its right
  /// on the same row. [accept] filters candidate values.
  ({OcrLine label, String value})? valueFor(RegExp label, bool Function(String value) accept) {
    for (final l in labelled(label)) {
      final inline = l.text.trim().replaceFirst(label, '').replaceFirst(RegExp(r'^[\s:;.\-]+'), '').trim();
      if (inline.isNotEmpty && accept(inline)) return (label: l, value: inline);

      OcrLine? best;
      for (final v in lines) {
        if (identical(v, l) || v.left < l.right - lineHeight || !accept(v.text.trim())) continue;
        final dy = (v.centerY - l.centerY).abs();
        if (dy > (l.height > v.height ? l.height : v.height) * 1.1) continue;
        if (best == null || dy < (best.centerY - l.centerY).abs()) best = v;
      }
      if (best != null) return (label: l, value: best.text.trim());
    }
    return null;
  }
}
