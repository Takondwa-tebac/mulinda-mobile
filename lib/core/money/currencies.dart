/// Supported currencies (must mirror the API's config/currency.php list),
/// each with a display name, symbol, and flag emoji for the picker.
class CurrencyInfo {
  const CurrencyInfo(this.code, this.name, this.symbol, this.flag);
  final String code;
  final String name;
  final String symbol;
  final String flag;
}

const kCurrencies = <CurrencyInfo>[
  CurrencyInfo('MWK', 'Malawian Kwacha', 'MK', '🇲🇼'),
  CurrencyInfo('USD', 'US Dollar', '\$', '🇺🇸'),
  CurrencyInfo('ZAR', 'South African Rand', 'R', '🇿🇦'),
  CurrencyInfo('KES', 'Kenyan Shilling', 'KSh', '🇰🇪'),
  CurrencyInfo('NGN', 'Nigerian Naira', '₦', '🇳🇬'),
  CurrencyInfo('GBP', 'British Pound', '£', '🇬🇧'),
  CurrencyInfo('EUR', 'Euro', '€', '🇪🇺'),
  CurrencyInfo('ZMW', 'Zambian Kwacha', 'ZK', '🇿🇲'),
  CurrencyInfo('TZS', 'Tanzanian Shilling', 'TSh', '🇹🇿'),
  CurrencyInfo('UGX', 'Ugandan Shilling', 'USh', '🇺🇬'),
];

/// Look up a currency by code, falling back to a neutral entry for unknowns.
CurrencyInfo currencyInfo(String code) => kCurrencies.firstWhere(
      (c) => c.code == code,
      orElse: () => CurrencyInfo(code, code, code, '🏳️'),
    );
