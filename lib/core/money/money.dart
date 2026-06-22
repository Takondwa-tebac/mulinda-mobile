/// Mirrors the API's money object: integer minor units + a preformatted string.
class Money {
  const Money({
    required this.minorUnits,
    required this.currency,
    required this.amount,
    required this.formatted,
  });

  final int minorUnits;
  final String currency;
  final double amount;
  final String formatted;

  static const zero = Money(minorUnits: 0, currency: 'MWK', amount: 0, formatted: 'MK 0');

  factory Money.fromJson(Map<String, dynamic> json) {
    return Money(
      minorUnits: (json['minor_units'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'MWK',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      formatted: json['formatted']?.toString() ?? '',
    );
  }

  /// Parse a money map that might be null, falling back to zero.
  static Money parse(dynamic value) {
    if (value is Map) return Money.fromJson(value.cast<String, dynamic>());
    return zero;
  }

  bool get isPositive => minorUnits > 0;
  bool get isNegative => minorUnits < 0;
}
