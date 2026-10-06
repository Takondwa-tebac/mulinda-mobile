import 'currencies.dart';

/// `MK 12,500.00` — symbol, thousands separators, two decimals (matches the
/// API's formatting so client-built records look identical to server ones).
String formatMoney(double major, String currency) {
  final symbol = currencyInfo(currency).symbol;
  final negative = major < 0;
  final parts = major.abs().toStringAsFixed(2).split('.');
  final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '${negative ? '-' : ''}$symbol $grouped.${parts[1]}';
}

/// A money object in the API's JSON shape, built on the device (for records
/// that exist only locally until they sync).
Map<String, dynamic> moneyJson(double major, String currency) => {
      'minor_units': (major * 100).round(),
      'currency': currency,
      'amount': major,
      'formatted': formatMoney(major, currency),
    };
