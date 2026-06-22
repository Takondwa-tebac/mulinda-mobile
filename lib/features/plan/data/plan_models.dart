import '../../../core/money/money.dart';

/// Read-only summaries of the three advisory endpoints for the Plan hub.
class AdvisorySummary {
  const AdvisorySummary({
    this.savingsRuleName,
    this.savingsOnTrack,
    this.targetRate,
    this.creditScore,
    this.creditBand,
    this.investRecommendation,
    this.riskPosture,
  });

  final String? savingsRuleName;
  final bool? savingsOnTrack;
  final double? targetRate;
  final int? creditScore;
  final String? creditBand;
  final String? investRecommendation;
  final String? riskPosture;

  factory AdvisorySummary.from(
    Map<String, dynamic>? savings,
    Map<String, dynamic>? credit,
    Map<String, dynamic>? invest,
  ) {
    final rule = (savings?['rule'] as Map?)?.cast<String, dynamic>();
    return AdvisorySummary(
      savingsRuleName: rule?['name']?.toString(),
      savingsOnTrack: savings?['on_track'] as bool?,
      targetRate: (savings?['target_savings_rate'] as num?)?.toDouble(),
      creditScore: (credit?['score'] as num?)?.toInt(),
      creditBand: credit?['band']?.toString(),
      investRecommendation: invest?['recommendation']?.toString(),
      riskPosture: invest?['risk_posture']?.toString(),
    );
  }
}

class GoalItem {
  const GoalItem({required this.id, required this.name, required this.target, required this.current});
  final String id;
  final String name;
  final Money target;
  final Money current;

  double get progress => target.minorUnits > 0
      ? (current.minorUnits / target.minorUnits).clamp(0, 1).toDouble()
      : 0;

  factory GoalItem.fromJson(Map<String, dynamic> j) => GoalItem(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        target: Money.parse(j['target']),
        current: Money.parse(j['current']),
      );
}

class BudgetItem {
  const BudgetItem({
    required this.id,
    required this.name,
    required this.spent,
    required this.limit,
    required this.percentage,
    required this.isExceeded,
  });
  final String id;
  final String name;
  final Money spent;
  final Money limit;
  final double percentage;
  final bool isExceeded;

  factory BudgetItem.fromJson(Map<String, dynamic> j) {
    final status = (j['status'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BudgetItem(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? (status['category']?.toString() ?? ''),
      spent: Money.parse(status['spent']),
      limit: Money.parse(status['limit'] ?? j['limit']),
      percentage: (status['percentage'] as num?)?.toDouble() ?? 0,
      isExceeded: status['is_exceeded'] == true,
    );
  }
}

class LoanItem {
  const LoanItem({required this.id, required this.name, required this.outstanding, required this.status});
  final String id;
  final String name;
  final Money outstanding;
  final String status;

  factory LoanItem.fromJson(Map<String, dynamic> j) {
    final progress = (j['progress'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LoanItem(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? '',
      outstanding: Money.parse(progress['outstanding']),
      status: j['status']?.toString() ?? 'active',
    );
  }
}

class InvestmentItem {
  const InvestmentItem({required this.id, required this.name, required this.value, required this.gain});
  final String id;
  final String name;
  final Money value;
  final Money gain;

  factory InvestmentItem.fromJson(Map<String, dynamic> j) => InvestmentItem(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        value: Money.parse(j['current_value']),
        gain: Money.parse(j['gain']),
      );
}

class ProjectItem {
  const ProjectItem({required this.id, required this.name, required this.spent, this.budget});
  final String id;
  final String name;
  final Money spent;
  final Money? budget;

  factory ProjectItem.fromJson(Map<String, dynamic> j) => ProjectItem(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        spent: Money.parse(j['spent']),
        budget: j['budget'] == null ? null : Money.parse(j['budget']),
      );
}
