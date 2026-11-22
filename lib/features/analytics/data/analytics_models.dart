import '../../../core/money/money.dart';

// Models for the analytics reports API (design/analytics-api-contract.md).
// The app renders what the server returns: no figure here is added up or
// derived on the device.

Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];
int _int(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);
int? _intOrNull(dynamic v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));
double? _doubleOrNull(dynamic v) => v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
String? _str(dynamic v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

/// `2026-10-24` (or a full timestamp) to a local calendar date.
DateTime? parseDay(dynamic v) {
  final s = _str(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  final local = s.length > 10 ? d.toLocal() : d;
  return DateTime(local.year, local.month, local.day);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The `period` query values the API accepts.
enum PeriodKey {
  today('today'),
  thisWeek('this_week'),
  thisMonth('this_month'),
  last30Days('last_30_days'),
  lastMonth('last_month'),
  custom('custom');

  const PeriodKey(this.api);

  final String api;

  static PeriodKey? fromApi(String? value) {
    for (final k in values) {
      if (k.api == value) return k;
    }
    return null;
  }
}

/// The period a report is asked for: a key, how many whole periods back
/// ([offset], 0 or negative), and the dates of a custom range.
class PeriodSelection {
  const PeriodSelection(this.key, {this.offset = 0, this.from, this.to});

  /// The owner's default: today plus the 29 days before.
  static const defaultPeriod = PeriodSelection(PeriodKey.last30Days);

  factory PeriodSelection.custom(DateTime from, DateTime to) => PeriodSelection(
    PeriodKey.custom,
    from: DateTime(from.year, from.month, from.day),
    to: DateTime(to.year, to.month, to.day),
  );

  final PeriodKey key;
  final int offset;
  final DateTime? from;
  final DateTime? to;

  /// The period before this one, same length.
  PeriodSelection get previous => PeriodSelection(key, offset: offset - 1, from: from, to: to);

  /// The period after this one; null when this one already includes today.
  PeriodSelection? get next => offset < 0 ? PeriodSelection(key, offset: offset + 1, from: from, to: to) : null;

  /// Query parameters for the analytics and transactions endpoints.
  Map<String, String> toParams() => {
    'period': key.api,
    if (key == PeriodKey.custom && from != null) 'from': _ymd(from!),
    if (key == PeriodKey.custom && to != null) 'to': _ymd(to!),
    if (offset != 0) 'offset': '$offset',
  };

  /// Read back from route query parameters (falls back to the default).
  static PeriodSelection fromParams(Map<String, String> q, {String prefix = ''}) {
    final key = PeriodKey.fromApi(q['${prefix}period']);
    if (key == null) return defaultPeriod;
    final offset = int.tryParse(q['${prefix}offset'] ?? '') ?? 0;
    final from = parseDay(q['${prefix}from']);
    final to = parseDay(q['${prefix}to']);
    if (key == PeriodKey.custom && (from == null || to == null)) return defaultPeriod;
    return PeriodSelection(key, offset: offset > 0 ? 0 : offset, from: from, to: to);
  }

  @override
  bool operator ==(Object other) =>
      other is PeriodSelection && other.key == key && other.offset == offset && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(key, offset, from, to);

  @override
  String toString() => 'PeriodSelection(${toParams()})';
}

/// The resolved period every analytics response carries.
class AnalyticsPeriod {
  const AnalyticsPeriod({
    required this.key,
    this.from,
    this.to,
    this.days = 0,
    this.elapsedDays = 0,
    this.inProgress = false,
    this.coverageFrom,
  });

  final PeriodKey? key;
  final DateTime? from;
  final DateTime? to;
  final int days;
  final int elapsedDays;

  /// True when the period includes today ("so far").
  final bool inProgress;

  /// The user's earliest transaction; null when there are none.
  final DateTime? coverageFrom;

  /// History starts inside this period, so it is not the full picture.
  bool get partlyCovered => coverageFrom != null && from != null && coverageFrom!.isAfter(from!);

  factory AnalyticsPeriod.fromJson(Map<String, dynamic> json) => AnalyticsPeriod(
    key: PeriodKey.fromApi(_str(json['key'])),
    from: parseDay(json['from']),
    to: parseDay(json['to']),
    days: _int(json['days']),
    elapsedDays: _int(json['elapsed_days'], _int(json['days'])),
    inProgress: json['in_progress'] == true,
    coverageFrom: parseDay(json['coverage_from']),
  );
}

enum ComparisonDirection { up, down, same }

/// How one figure compares with the same-length window before it.
class Comparison {
  const Comparison({
    required this.comparable,
    this.reason,
    this.previousFrom,
    this.previousTo,
    this.previousAmount,
    this.difference,
    this.direction,
    this.pct,
    this.showPct = false,
  });

  static const unavailable = Comparison(comparable: false);

  final bool comparable;

  /// `insufficient_history`, `in_progress_day` or null.
  final String? reason;
  final DateTime? previousFrom;
  final DateTime? previousTo;
  final Money? previousAmount;

  /// Always positive; [direction] says which way.
  final Money? difference;
  final ComparisonDirection? direction;
  final double? pct;

  /// Only true when the server decided a percentage is meaningful.
  final bool showPct;

  bool get insufficientHistory => reason == 'insufficient_history';
  bool get dayInProgress => reason == 'in_progress_day';

  static Comparison parse(dynamic value) => value is Map ? Comparison.fromJson(value.cast<String, dynamic>()) : unavailable;

  factory Comparison.fromJson(Map<String, dynamic> json) {
    final previous = _map(json['previous']);
    final comparable = json['comparable'] == true;
    return Comparison(
      comparable: comparable,
      reason: _str(json['reason']),
      previousFrom: parseDay(previous['from']),
      previousTo: parseDay(previous['to']),
      previousAmount: Money.parseOrNull(previous['amount']),
      difference: Money.parseOrNull(json['difference']),
      direction: switch (_str(json['direction'])) {
        'up' => ComparisonDirection.up,
        'down' => ComparisonDirection.down,
        'same' => ComparisonDirection.same,
        _ => null,
      },
      pct: _doubleOrNull(json['pct']),
      showPct: json['show_pct'] == true,
    );
  }
}

/// Where an insight leads when tapped.
class InsightTarget {
  const InsightTarget({required this.type, required this.id});

  /// `category`, `transaction` or `day`.
  final String type;
  final String id;

  static InsightTarget? parse(dynamic value) {
    final m = _map(value);
    final type = _str(m['type']);
    final id = _str(m['id']);
    if (type == null || id == null) return null;
    return InsightTarget(type: type, id: id);
  }
}

/// A fact the server found worth saying. The app owns the wording
/// (`analytics.insight.<key>`), filled in from [params].
class Insight {
  const Insight({required this.key, this.params = const {}, this.target, this.priority = 0});

  final String key;
  final Map<String, dynamic> params;
  final InsightTarget? target;
  final int priority;

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
    key: json['key']?.toString() ?? '',
    params: _map(json['params']),
    target: InsightTarget.parse(json['target']),
    priority: _int(json['priority']),
  );

  static List<Insight> parseList(dynamic value) {
    final list = _maps(value).map(Insight.fromJson).where((i) => i.key.isNotEmpty).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return list.take(3).toList();
  }
}

/// `{id, name, icon, color}` of a category.
class CategoryRef {
  const CategoryRef({this.id, this.name, this.icon, this.color});

  final String? id;
  final String? name;
  final String? icon;
  final String? color;

  static CategoryRef? parse(dynamic value) {
    if (value is! Map) return null;
    final m = value.cast<String, dynamic>();
    return CategoryRef(id: _str(m['id']), name: _str(m['name']), icon: _str(m['icon']), color: _str(m['color']));
  }
}

/// A transaction pointed at by a report (highest, lowest, biggest).
class TxnRef {
  const TxnRef({required this.id, required this.title, required this.amount, this.occurredAt, this.category});

  final String id;
  final String title;
  final Money amount;
  final DateTime? occurredAt;
  final CategoryRef? category;

  static TxnRef? parse(dynamic value) {
    if (value is! Map) return null;
    final m = value.cast<String, dynamic>();
    final id = _str(m['id']);
    if (id == null) return null;
    return TxnRef(
      id: id,
      title: m['title']?.toString() ?? '',
      amount: Money.parse(m['amount']),
      occurredAt: parseDay(m['occurred_at']),
      category: CategoryRef.parse(m['category']),
    );
  }
}

/// One day of a summary's series.
class SeriesPoint {
  const SeriesPoint({required this.date, required this.expense, required this.income, this.count = 0, this.complete = true});

  final DateTime date;
  final Money expense;
  final Money income;
  final int count;

  /// False for today, which is not over yet.
  final bool complete;

  static SeriesPoint? fromJson(Map<String, dynamic> json) {
    final date = parseDay(json['date']);
    if (date == null) return null;
    return SeriesPoint(
      date: date,
      expense: Money.parse(json['expense']),
      income: Money.parse(json['income']),
      count: _int(json['count']),
      complete: json['complete'] != false,
    );
  }
}

/// Money left out of the totals (own transfers, money sent and returned).
class NotCounted {
  const NotCounted({required this.amount, this.count = 0});

  static const none = NotCounted(amount: Money.zero);

  final Money amount;
  final int count;

  factory NotCounted.fromJson(Map<String, dynamic> json) =>
      NotCounted(amount: Money.parse(json['amount']), count: _int(json['count']));
}

/// `GET /v1/analytics/summary`.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.period,
    required this.income,
    required this.expense,
    required this.net,
    this.expenseCount = 0,
    this.incomeCount = 0,
    this.totalCount = 0,
    required this.averagePerDay,
    this.typicalDay,
    this.biggestExpense,
    this.expenseComparison = Comparison.unavailable,
    this.incomeComparison = Comparison.unavailable,
    this.series,
    this.topCategoriesShare,
    this.notCounted = NotCounted.none,
    this.insights = const [],
  });

  final AnalyticsPeriod period;
  final Money income;
  final Money expense;
  final Money net;
  final int expenseCount;
  final int incomeCount;
  final int totalCount;
  final Money averagePerDay;
  final Money? typicalDay;
  final TxnRef? biggestExpense;
  final Comparison expenseComparison;
  final Comparison incomeComparison;

  /// One point per day; null for "today".
  final List<SeriesPoint>? series;
  final int? topCategoriesShare;
  final NotCounted notCounted;
  final List<Insight> insights;

  /// Nothing came in or went out in the period.
  bool get isEmpty => totalCount == 0 && expense.minorUnits == 0 && income.minorUnits == 0;

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    final counts = _map(json['counts']);
    final comparison = _map(json['comparison']);
    final series = json['series'];
    return AnalyticsSummary(
      period: AnalyticsPeriod.fromJson(_map(json['period'])),
      income: Money.parse(json['income']),
      expense: Money.parse(json['expense']),
      net: Money.parse(json['net']),
      expenseCount: _int(counts['expense']),
      incomeCount: _int(counts['income']),
      totalCount: _int(counts['total']),
      averagePerDay: Money.parse(json['average_per_day']),
      typicalDay: Money.parseOrNull(json['typical_day']),
      biggestExpense: TxnRef.parse(json['biggest_expense']),
      expenseComparison: Comparison.parse(comparison['expense']),
      incomeComparison: Comparison.parse(comparison['income']),
      series: series is List ? _maps(series).map(SeriesPoint.fromJson).whereType<SeriesPoint>().toList() : null,
      topCategoriesShare: _intOrNull(json['top_categories_share']),
      notCounted: NotCounted.fromJson(_map(json['not_counted'])),
      insights: Insight.parseList(json['insights']),
    );
  }
}

/// `expense` or `income`.
enum ReportKind {
  expense,
  income;

  static ReportKind fromApi(String? v) => v == 'income' ? ReportKind.income : ReportKind.expense;
}

/// One category row of a breakdown, after the server's grouping.
class CategoryRow {
  const CategoryRow({
    this.categoryId,
    this.name,
    this.icon,
    this.color,
    required this.amount,
    this.sharePct = 0,
    this.count = 0,
    this.previousAmount,
    this.comparison = Comparison.unavailable,
    this.needsCategory = false,
  });

  /// Null for Uncategorised.
  final String? categoryId;

  /// Null for Uncategorised (the app shows "Uncategorised").
  final String? name;
  final String? icon;
  final String? color;
  final Money amount;
  final int sharePct;
  final int count;
  final Money? previousAmount;
  final Comparison comparison;
  final bool needsCategory;

  bool get isUncategorised => categoryId == null;

  /// The id for `/analytics/categories/{id}`.
  String get routeId => categoryId ?? 'uncategorised';

  factory CategoryRow.fromJson(Map<String, dynamic> json) => CategoryRow(
    categoryId: _str(json['category_id']),
    name: _str(json['name']),
    icon: _str(json['icon']),
    color: _str(json['color']),
    amount: Money.parse(json['amount']),
    sharePct: _int(json['share_pct']),
    count: _int(json['count']),
    previousAmount: Money.parseOrNull(json['previous_amount']),
    comparison: Comparison.parse(json['comparison']),
    needsCategory: json['needs_category'] == true,
  );
}

/// "Everything else": the categories too small to name.
class OthersGroup {
  const OthersGroup({required this.amount, this.sharePct = 0, this.count = 0, this.members = const []});

  final Money amount;
  final int sharePct;
  final int count;
  final List<CategoryRow> members;

  static OthersGroup? parse(dynamic value) {
    if (value is! Map) return null;
    final m = value.cast<String, dynamic>();
    return OthersGroup(
      amount: Money.parse(m['amount']),
      sharePct: _int(m['share_pct']),
      count: _int(m['count']),
      members: _maps(m['members']).map(CategoryRow.fromJson).toList(),
    );
  }
}

/// Who money came from (income only).
class Party {
  const Party({required this.name, required this.amount, this.count = 0});

  final String name;
  final Money amount;
  final int count;

  factory Party.fromJson(Map<String, dynamic> json) =>
      Party(name: json['name']?.toString() ?? '', amount: Money.parse(json['amount']), count: _int(json['count']));
}

/// `GET /v1/analytics/categories`.
class CategoryBreakdown {
  const CategoryBreakdown({
    required this.period,
    this.kind = ReportKind.expense,
    required this.total,
    this.count = 0,
    this.rows = const [],
    this.others,
    this.notCounted = NotCounted.none,
    this.parties = const [],
    this.comparison = Comparison.unavailable,
    this.insights = const [],
  });

  final AnalyticsPeriod period;
  final ReportKind kind;
  final Money total;
  final int count;
  final List<CategoryRow> rows;
  final OthersGroup? others;
  final NotCounted notCounted;
  final List<Party> parties;
  final Comparison comparison;
  final List<Insight> insights;

  bool get isEmpty => total.minorUnits == 0 && rows.isEmpty && others == null;

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) => CategoryBreakdown(
    period: AnalyticsPeriod.fromJson(_map(json['period'])),
    kind: ReportKind.fromApi(_str(json['kind'])),
    total: Money.parse(json['total']),
    count: _int(json['count']),
    rows: _maps(json['rows']).map(CategoryRow.fromJson).toList(),
    others: OthersGroup.parse(json['others']),
    notCounted: NotCounted.fromJson(_map(json['not_counted'])),
    parties: _maps(json['parties']).map(Party.fromJson).toList(),
    comparison: Comparison.parse(json['comparison']),
    insights: Insight.parseList(json['insights']),
  );
}

/// One month of a category trend.
class TrendPoint {
  const TrendPoint({required this.start, required this.amount, this.count = 0, this.complete = true});

  final DateTime start;
  final Money amount;
  final int count;

  /// False for the current month, drawn dashed and labelled "so far".
  final bool complete;

  static TrendPoint? fromJson(Map<String, dynamic> json) {
    final start = parseDay(json['start']);
    if (start == null) return null;
    return TrendPoint(
      start: start,
      amount: Money.parse(json['amount']),
      count: _int(json['count']),
      complete: json['complete'] != false,
    );
  }
}

class CategoryTrend {
  const CategoryTrend({this.unit = 'month', this.points = const []});

  final String unit;
  final List<TrendPoint> points;

  static CategoryTrend? parse(dynamic value) {
    if (value is! Map) return null;
    final m = value.cast<String, dynamic>();
    final points = _maps(m['points']).map(TrendPoint.fromJson).whereType<TrendPoint>().toList();
    if (points.isEmpty) return null;
    return CategoryTrend(unit: m['unit']?.toString() ?? 'month', points: points);
  }
}

/// A place money in a category went (or came from).
class MerchantShare {
  const MerchantShare({this.name, required this.amount, this.count = 0, this.sharePct = 0});

  /// Null for "Other places".
  final String? name;
  final Money amount;
  final int count;
  final int sharePct;

  factory MerchantShare.fromJson(Map<String, dynamic> json) => MerchantShare(
    name: _str(json['name']),
    amount: Money.parse(json['amount']),
    count: _int(json['count']),
    sharePct: _int(json['share_pct']),
  );
}

/// `GET /v1/analytics/categories/{id|uncategorised}`.
class CategoryDetail {
  const CategoryDetail({
    required this.period,
    this.kind = ReportKind.expense,
    this.category,
    required this.total,
    this.sharePct = 0,
    this.count = 0,
    this.average,
    this.median,
    this.highest,
    this.lowest,
    this.comparison = Comparison.unavailable,
    this.trend,
    this.steady,
    this.merchants = const [],
    this.insights = const [],
  });

  final AnalyticsPeriod period;
  final ReportKind kind;

  /// Null for Uncategorised.
  final CategoryRef? category;
  final Money total;
  final int sharePct;
  final int count;

  /// Null when there are no payments.
  final Money? average;

  /// Null below 5 payments.
  final Money? median;

  /// Null below 2 payments.
  final TxnRef? highest;
  final TxnRef? lowest;
  final Comparison comparison;

  /// Null with fewer than 3 complete months of history.
  final CategoryTrend? trend;
  final bool? steady;
  final List<MerchantShare> merchants;
  final List<Insight> insights;

  factory CategoryDetail.fromJson(Map<String, dynamic> json) {
    final steady = json['steady'];
    return CategoryDetail(
      period: AnalyticsPeriod.fromJson(_map(json['period'])),
      kind: ReportKind.fromApi(_str(json['kind'])),
      category: CategoryRef.parse(json['category']),
      total: Money.parse(json['total']),
      sharePct: _int(json['share_pct']),
      count: _int(json['count']),
      average: Money.parseOrNull(json['average']),
      median: Money.parseOrNull(json['median']),
      highest: TxnRef.parse(json['highest']),
      lowest: TxnRef.parse(json['lowest']),
      comparison: Comparison.parse(json['comparison']),
      trend: CategoryTrend.parse(json['trend']),
      steady: steady is bool ? steady : null,
      merchants: _maps(json['merchants']).map(MerchantShare.fromJson).toList(),
      insights: Insight.parseList(json['insights']),
    );
  }
}

/// The shop or person of a transaction within the report period.
class ContextMerchant {
  const ContextMerchant({required this.name, this.count = 0, required this.total});

  final String name;
  final int count;
  final Money total;

  static ContextMerchant? parse(dynamic value) {
    if (value is! Map) return null;
    final m = value.cast<String, dynamic>();
    final name = _str(m['name']);
    if (name == null) return null;
    return ContextMerchant(name: name, count: _int(m['count']), total: Money.parse(m['total']));
  }
}

/// `context` on `GET /v1/transactions/{id}?context_period=`: one payment
/// placed in its category and with its shop for the period of the report.
class TxnContext {
  const TxnContext({
    required this.period,
    this.categoryTotal,
    this.shareOfCategoryPct,
    this.rankInCategory,
    this.categoryCount,
    this.merchant,
  });

  final AnalyticsPeriod period;
  final Money? categoryTotal;
  final int? shareOfCategoryPct;
  final int? rankInCategory;
  final int? categoryCount;
  final ContextMerchant? merchant;

  /// Nothing worth showing.
  bool get isEmpty =>
      (categoryTotal == null || shareOfCategoryPct == null) &&
      !(rankInCategory == 1 && (categoryCount ?? 0) >= 2) &&
      merchant == null;

  static TxnContext? parse(dynamic value) {
    if (value is! Map) return null;
    final m = value.cast<String, dynamic>();
    return TxnContext(
      period: AnalyticsPeriod.fromJson(_map(m['period'])),
      categoryTotal: Money.parseOrNull(m['category_total']),
      shareOfCategoryPct: _intOrNull(m['share_of_category_pct']),
      rankInCategory: _intOrNull(m['rank_in_category']),
      categoryCount: _intOrNull(m['category_count']),
      merchant: ContextMerchant.parse(m['merchant']),
    );
  }
}
