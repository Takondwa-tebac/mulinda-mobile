/// Income bands: (API enum value, translation key prefix). The keys resolve to
/// `<prefix>.label` and `<prefix>.range` in the translation files.
const kIncomeBands = <(String, String)>[
  ('low', 'income.low'),
  ('lower_middle', 'income.lowerMiddle'),
  ('middle', 'income.middle'),
  ('upper_middle', 'income.upperMiddle'),
  ('upper', 'income.upper'),
];

/// Translation-key prefix for a bracket value, or null if unknown/unset.
String? incomeBandKey(String? value) {
  for (final band in kIncomeBands) {
    if (band.$1 == value) return band.$2;
  }
  return null;
}
