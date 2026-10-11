// What each kind of holding records, as described by the server
// (`GET /v1/investment-types`). The form is built from this, so a new kind of
// holding needs no app update.

class InvestmentOption {
  const InvestmentOption(this.value, this.labels);

  final String value;
  final Map<String, String> labels;

  String label(String lang) => _pick(labels, lang);
}

class InvestmentField {
  const InvestmentField({
    required this.key,
    required this.kind,
    required this.required,
    required this.labels,
    this.options = const [],
    this.suggestions = const [],
  });

  final String key;

  /// text | number | money | percent | date | select
  final String kind;
  final bool required;
  final Map<String, String> labels;
  final List<InvestmentOption> options;

  /// Ideas to pick from while typing (value = a short code, label = the name);
  /// anything else may still be typed.
  final List<InvestmentOption> suggestions;

  String label(String lang) => _pick(labels, lang);

  bool get isNumeric => kind == 'number' || kind == 'money' || kind == 'percent';

  factory InvestmentField.fromJson(Map<String, dynamic> j) => InvestmentField(
        key: j['key'].toString(),
        kind: j['kind']?.toString() ?? 'text',
        required: j['required'] == true,
        labels: _labels(j['label']),
        options: [
          for (final o in (j['options'] as List? ?? const []))
            InvestmentOption((o as Map)['value'].toString(), _labels(o['label'])),
        ],
        suggestions: [
          for (final o in (j['suggestions'] is List ? j['suggestions'] as List : const []))
            InvestmentOption((o as Map)['value'].toString(), {'en': o['label'].toString()}),
        ],
      );
}

class InvestmentTypeDef {
  const InvestmentTypeDef({
    required this.type,
    required this.labels,
    this.descriptions = const {},
    this.valuation = 'recorded',
    this.requiresMaturity = false,
    this.interest = false,
    this.derivesAmountInvested = false,
    this.derivesValue = false,
    this.derivation = const {},
    this.fields = const [],
  });

  final String type;
  final Map<String, String> labels;
  final Map<String, String> descriptions;

  /// term | running_interest | recorded | units_x_price | periodic
  final String valuation;
  final bool requiresMaturity;

  /// Asks for an expected return and how it is paid.
  final bool interest;

  /// The amount invested / current value follow from the details, so they are
  /// shown as worked out instead of asked for.
  final bool derivesAmountInvested;
  final bool derivesValue;

  /// Which fields feed the figures (contribution_field, count_field, value_field, value_fields).
  final Map<String, dynamic> derivation;
  final List<InvestmentField> fields;

  String label(String lang) => _pick(labels, lang);
  String? description(String lang) => descriptions.isEmpty ? null : _pick(descriptions, lang);

  factory InvestmentTypeDef.fromJson(Map<String, dynamic> j) => InvestmentTypeDef(
        type: j['type'].toString(),
        labels: _labels(j['label']),
        descriptions: _labels(j['description']),
        valuation: j['valuation']?.toString() ?? 'recorded',
        requiresMaturity: j['requires_maturity'] == true,
        interest: j['interest'] == true,
        derivesAmountInvested: j['derives_amount_invested'] == true,
        derivesValue: j['derives_value'] == true,
        derivation: (j['derivation'] is Map) ? (j['derivation'] as Map).cast<String, dynamic>() : const {},
        fields: [
          for (final f in (j['fields'] as List? ?? const [])) InvestmentField.fromJson((f as Map).cast<String, dynamic>()),
        ],
      );

  /// Worked out from the typed details, for showing while the user types. The
  /// server works the same figures out again when it saves, and its answer wins.
  ({double? invested, double? value}) derive(Map<String, double?> n) {
    switch (valuation) {
      case 'units_x_price':
        final units = n['units'], buy = n['buy_price'];
        if (units == null || buy == null) return (invested: null, value: null);
        final price = n['current_price'];
        return (invested: _round(units * buy + (n['fees'] ?? 0)), value: price == null ? null : _round(units * price));
      case 'periodic':
        final contribution = n[derivation['contribution_field']?.toString()];
        final count = n[derivation['count_field']?.toString()];
        if (contribution == null || count == null) return (invested: null, value: null);
        final invested = _round(contribution * count);
        final recorded = n[derivation['value_field']?.toString()];
        return (invested: invested, value: recorded ?? invested);
      case 'recorded':
        final keys = (derivation['value_fields'] as List?)?.map((e) => e.toString()) ?? const <String>[];
        final parts = [for (final k in keys) if (n[k] != null) n[k]!];
        return (invested: null, value: parts.isEmpty ? null : _round(parts.fold<double>(0, (a, b) => a + b)));
      default:
        return (invested: null, value: null);
    }
  }
}

double _round(double v) => (v * 100).round() / 100;

Map<String, String> _labels(dynamic v) =>
    v is Map ? {for (final e in v.entries) e.key.toString(): e.value.toString()} : <String, String>{};

String _pick(Map<String, String> labels, String lang) => labels[lang] ?? labels['en'] ?? (labels.isEmpty ? '' : labels.values.first);

/// Used when the server's list cannot be loaded (offline, an older server): the
/// kinds that existed before the catalog, with the plain form.
const fallbackInvestmentTypes = <InvestmentTypeDef>[
  InvestmentTypeDef(type: 'fixed_deposit', labels: {'en': 'Fixed deposit'}, valuation: 'term', requiresMaturity: true, interest: true),
  InvestmentTypeDef(type: 'treasury_bill', labels: {'en': 'Treasury bill'}, valuation: 'term', requiresMaturity: true, interest: true),
  InvestmentTypeDef(type: 'treasury_bond', labels: {'en': 'Treasury bond'}, valuation: 'term', requiresMaturity: true, interest: true),
  InvestmentTypeDef(type: 'unit_trust', labels: {'en': 'Unit trust'}, interest: true),
  InvestmentTypeDef(type: 'shares', labels: {'en': 'Shares'}),
  InvestmentTypeDef(type: 'pension', labels: {'en': 'Pension'}),
  InvestmentTypeDef(type: 'business', labels: {'en': 'Business'}),
  InvestmentTypeDef(type: 'property', labels: {'en': 'Property'}),
  InvestmentTypeDef(type: 'other', labels: {'en': 'Other'}, interest: true),
];
