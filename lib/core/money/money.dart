/// Mirrors the API's money object: integer minor units + a preformatted string.
class Money {
  const Money({
    required this.minorUnits,
    required this.currency,
    required this.amount,
    required this.formatted,
    this.formattedWhole,
  });

  final int minorUnits;
  final String currency;
  final double amount;
  final String formatted;

  /// `MK 285,400`: rounded to whole major units, for headlines, report rows
  /// and chart labels. Null when the server did not send it.
  final String? formattedWhole;

  /// [formattedWhole] when the server sent it, otherwise [formatted].
  String get whole => (formattedWhole?.isNotEmpty ?? false) ? formattedWhole! : formatted;

  static const zero = Money(minorUnits: 0, currency: 'MWK', amount: 0, formatted: 'MK 0');

  factory Money.fromJson(Map<String, dynamic> json) {
    return Money(
      minorUnits: (json['minor_units'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'MWK',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      formatted: json['formatted']?.toString() ?? '',
      formattedWhole: json['formatted_whole']?.toString(),
    );
  }

  /// Parse a money map, or null when it is missing.
  static Money? parseOrNull(dynamic value) => value is Map ? Money.fromJson(value.cast<String, dynamic>()) : null;

  /// Parse a money map that might be null, falling back to zero.
  static Money parse(dynamic value) {
    if (value is Map) return Money.fromJson(value.cast<String, dynamic>());
    return zero;
  }

  bool get isPositive => minorUnits > 0;
  bool get isNegative => minorUnits < 0;
}
