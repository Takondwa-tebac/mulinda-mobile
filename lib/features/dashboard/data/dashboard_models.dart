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

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> obj(String key) =>
        (json[key] as Map?)?.cast<String, dynamic>() ?? const {};

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
      recent: (json['recent_transactions'] as List?)
              ?.map((e) => RecentTxn.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }
}

class MonthSummary {
  const MonthSummary({
    required this.income,
    required this.expense,
    required this.net,
    required this.savingsRate,
  });

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
    Map<String, dynamic> obj(String key) =>
        (json[key] as Map?)?.cast<String, dynamic>() ?? const {};
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
  });

  final String id;
  final String date;
  final String type; // income | expense
  final Money amount;
  final String? merchant;
  final String? category;

  bool get isIncome => type == 'income';

  factory RecentTxn.fromJson(Map<String, dynamic> json) {
    return RecentTxn(
      id: json['id'].toString(),
      date: json['date']?.toString() ?? '',
      type: json['type']?.toString() ?? 'expense',
      amount: Money.parse(json['amount']),
      merchant: json['merchant']?.toString(),
      category: json['category']?.toString(),
    );
  }
}
