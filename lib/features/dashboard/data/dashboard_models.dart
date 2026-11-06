import '../../../core/money/money.dart';

/// The home-screen snapshot from GET /v1/dashboard.
class DashboardSummary {
  const DashboardSummary({
    required this.netWorth,
    required this.thisMonth,
    required this.indicators,
    required this.budgetsTotal,
    required this.budgetsExceeded,
    required this.goalsActive,
    required this.loansActive,
    required this.loansOutstanding,
    required this.investmentsCount,
    required this.investmentsValue,
    required this.investmentsGain,
    required this.projectsActive,
    required this.recent,
    this.needsAttention,
    this.spendingByCategory = const [],
  });

  final Money netWorth;
  final MonthSummary thisMonth;
  final Indicators indicators;
  final int budgetsTotal;
  final int budgetsExceeded;
  final int goalsActive;
  final int loansActive;
  final Money loansOutstanding;
  final int investmentsCount;
  final Money investmentsValue;
  final Money investmentsGain;
  final int projectsActive;
  final List<RecentTxn> recent;

  /// Transactions whose category needs a look; null when the server is older
  /// and does not report it.
  final int? needsAttention;

  /// This month to date vs the same days last month, expenses only. Empty when
  /// the server does not send it.
  final List<CategorySpend> spendingByCategory;

  /// Nothing recorded yet: no balance, no activity, no plans.
  bool get isFirstRun =>
      recent.isEmpty &&
      netWorth.minorUnits == 0 &&
      thisMonth.income.minorUnits == 0 &&
      thisMonth.expense.minorUnits == 0 &&
      budgetsTotal == 0 &&
      goalsActive == 0 &&
      loansActive == 0 &&
      investmentsCount == 0;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> obj(String key) => (json[key] as Map?)?.cast<String, dynamic>() ?? const {};

    final budgets = obj('budgets');
    final goals = obj('goals');
    final loans = obj('loans');
    final investments = obj('investments');
    final projects = obj('projects');

    return DashboardSummary(
      netWorth: Money.parse(json['net_worth']),
      thisMonth: MonthSummary.fromJson(obj('this_month')),
      indicators: Indicators.fromJson(obj('indicators')),
      budgetsTotal: (budgets['total'] as num?)?.toInt() ?? 0,
      budgetsExceeded: (budgets['exceeded'] as num?)?.toInt() ?? 0,
      goalsActive: (goals['active'] as num?)?.toInt() ?? 0,
      loansActive: (loans['active'] as num?)?.toInt() ?? 0,
      loansOutstanding: Money.parse(loans['total_outstanding']),
      investmentsCount: (investments['count'] as num?)?.toInt() ?? 0,
      investmentsValue: Money.parse(investments['total_value']),
      investmentsGain: Money.parse(investments['total_gain']),
      projectsActive: (projects['active'] as num?)?.toInt() ?? 0,
      recent:
          (json['recent_transactions'] as List?)
              ?.map((e) => RecentTxn.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      needsAttention: (obj('categorisation')['needs_attention'] as num?)?.toInt(),
      spendingByCategory:
          (json['spending_by_category'] as List?)
              ?.whereType<Map>()
              .map((e) => CategorySpend.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }
}

/// One row of `spending_by_category`.
class CategorySpend {
  const CategorySpend({
    this.categoryId,
    required this.name,
    this.icon,
    this.color,
    required this.amount,
    required this.previousAmount,
  });

  /// Null for "Other" / uncategorised.
  final String? categoryId;
  final String name;
  final String? icon;
  final String? color;
  final Money amount;
  final Money previousAmount;

  factory CategorySpend.fromJson(Map<String, dynamic> json) => CategorySpend(
    categoryId: json['category_id']?.toString(),
    name: json['name']?.toString() ?? '',
    icon: json['icon']?.toString(),
    color: json['color']?.toString(),
    amount: Money.parse(json['amount']),
    previousAmount: Money.parse(json['previous_amount']),
  );
}

class MonthSummary {
  const MonthSummary({required this.income, required this.expense, required this.net, required this.savingsRate});

  final Money income;
  final Money expense;
  final Money net;
  final double savingsRate;

  factory MonthSummary.fromJson(Map<String, dynamic> json) {
    return MonthSummary(
      income: Money.parse(json['income']),
      expense: Money.parse(json['expense']),
      net: Money.parse(json['net']),
      savingsRate: (json['savings_rate'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Indicators {
  const Indicators({
    required this.healthScore,
    required this.healthGrade,
    required this.creditScore,
    required this.creditBand,
    required this.savingsRuleName,
    required this.savingsOnTrack,
  });

  final int healthScore;
  final String healthGrade;
  final int creditScore;
  final String creditBand;
  final String savingsRuleName;
  final bool savingsOnTrack;

  factory Indicators.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> obj(String key) => (json[key] as Map?)?.cast<String, dynamic>() ?? const {};
    final health = obj('health_score');
    final credit = obj('creditworthiness');
    final savings = obj('savings_rule');

    return Indicators(
      healthScore: (health['score'] as num?)?.toInt() ?? 0,
      healthGrade: health['grade']?.toString() ?? '–',
      creditScore: (credit['score'] as num?)?.toInt() ?? 0,
      creditBand: credit['band']?.toString() ?? '–',
      savingsRuleName: savings['name']?.toString() ?? '',
      savingsOnTrack: savings['on_track'] == true,
    );
  }
}

class RecentTxn {
  const RecentTxn({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    this.merchant,
    this.category,
    this.categoryIcon,
    this.categoryColor,
    this.categoryIsSpending = true,
    this.needsAttention = false,
    this.categorisationStatus,
  });

  final String id;
  final String date;
  final String type; // income | expense | transfer
  final Money amount;
  final String? merchant;
  final String? category;
  final String? categoryIcon;
  final String? categoryColor;
  final bool categoryIsSpending;

  /// From the optional `categorisation` block; false when absent (older API).
  final bool needsAttention;
  final String? categorisationStatus;

  bool get isIncome => type == 'income';

  /// An expense in a category that is not spending ("Moving my money").
  bool get notSpending => type == 'expense' && category != null && !categoryIsSpending;

  factory RecentTxn.fromJson(Map<String, dynamic> json) {
    // Newer servers send `category_detail` next to the plain `category` name;
    // some send `category` itself as an object. Older ones send only the name.
    final detail = json['category_detail'] is Map
        ? (json['category_detail'] as Map).cast<String, dynamic>()
        : (json['category'] is Map ? (json['category'] as Map).cast<String, dynamic>() : null);
    final categorisation = json['categorisation'] is Map
        ? (json['categorisation'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final type = json['type']?.toString() ?? 'expense';
    return RecentTxn(
      id: json['id'].toString(),
      date: json['date']?.toString() ?? '',
      type: type,
      amount: Money.parse(json['amount']),
      merchant: json['merchant']?.toString(),
      category: detail?['name']?.toString() ?? (json['category'] is String ? json['category'] as String : null),
      categoryIcon: (detail?['icon'] ?? json['category_icon'])?.toString(),
      categoryColor: (detail?['color'] ?? json['category_color'])?.toString(),
      categoryIsSpending: detail?['is_spending'] != false,
      needsAttention: type != 'transfer' && categorisation['needs_attention'] == true,
      categorisationStatus: categorisation['status']?.toString(),
    );
  }
}
