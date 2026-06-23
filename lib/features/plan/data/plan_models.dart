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

double? _num(dynamic v) => (v as num?)?.toDouble();
String? _str(dynamic v) => v?.toString();

class GoalItem {
  const GoalItem({
    required this.id,
    required this.name,
    required this.type,
    required this.target,
    required this.current,
    this.targetDate,
    this.monthlyContribution,
  });

  final String id;
  final String name;
  final String type;
  final Money target;
  final Money current;
  final String? targetDate;
  final Money? monthlyContribution;

  double get progress => target.minorUnits > 0
      ? (current.minorUnits / target.minorUnits).clamp(0, 1).toDouble()
      : 0;

  factory GoalItem.fromJson(Map<String, dynamic> j) => GoalItem(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        type: j['type']?.toString() ?? 'custom',
        target: Money.parse(j['target']),
        current: Money.parse(j['current']),
        targetDate: _str(j['target_date']),
        monthlyContribution: j['monthly_contribution'] == null ? null : Money.parse(j['monthly_contribution']),
      );
}

class BudgetItem {
  const BudgetItem({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.period,
    required this.limit,
    required this.spent,
    required this.percentage,
    required this.isExceeded,
    required this.alertThreshold,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String period;
  final Money limit;
  final Money spent;
  final double percentage;
  final bool isExceeded;
  final double alertThreshold;
  final bool isActive;

  factory BudgetItem.fromJson(Map<String, dynamic> j) {
    final status = (j['status'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BudgetItem(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? (status['category']?.toString() ?? ''),
      categoryId: _str(j['category_id']),
      period: j['period']?.toString() ?? 'monthly',
      limit: Money.parse(j['limit'] ?? status['limit']),
      spent: Money.parse(status['spent']),
      percentage: _num(status['percentage']) ?? 0,
      isExceeded: status['is_exceeded'] == true,
      alertThreshold: _num(j['alert_threshold']) ?? 0.8,
      isActive: j['is_active'] != false,
    );
  }
}

class LoanItem {
  const LoanItem({
    required this.id,
    required this.name,
    this.lender,
    required this.principal,
    required this.annualInterestRate,
    required this.interestType,
    required this.termMonths,
    required this.status,
    required this.disbursedAt,
    this.firstPaymentDate,
    required this.outstanding,
  });

  final String id;
  final String name;
  final String? lender;
  final Money principal;
  final double annualInterestRate;
  final String interestType;
  final int termMonths;
  final String status;
  final String? disbursedAt;
  final String? firstPaymentDate;
  final Money outstanding;

  factory LoanItem.fromJson(Map<String, dynamic> j) {
    final progress = (j['progress'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LoanItem(
      id: j['id'].toString(),
      name: j['name']?.toString() ?? '',
      lender: _str(j['lender']),
      principal: Money.parse(j['principal']),
      annualInterestRate: _num(j['annual_interest_rate']) ?? 0,
      interestType: j['interest_type']?.toString() ?? 'reducing_balance',
      termMonths: (j['term_months'] as num?)?.toInt() ?? 12,
      status: j['status']?.toString() ?? 'active',
      disbursedAt: _str(j['disbursed_at']),
      firstPaymentDate: _str(j['first_payment_date']),
      outstanding: Money.parse(progress['outstanding']),
    );
  }
}

class InvestmentItem {
  const InvestmentItem({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.amountInvested,
    required this.value,
    required this.gain,
    this.expectedReturn,
    this.startedAt,
    this.maturityDate,
    this.notes,
  });

  final String id;
  final String name;
  final String type;
  final String status;
  final Money amountInvested;
  final Money value;
  final Money gain;
  final double? expectedReturn;
  final String? startedAt;
  final String? maturityDate;
  final String? notes;

  factory InvestmentItem.fromJson(Map<String, dynamic> j) => InvestmentItem(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        type: j['type']?.toString() ?? 'other',
        status: j['status']?.toString() ?? 'active',
        amountInvested: Money.parse(j['amount_invested']),
        value: Money.parse(j['current_value']),
        gain: Money.parse(j['gain']),
        expectedReturn: _num(j['expected_annual_return']),
        startedAt: _str(j['started_at']),
        maturityDate: _str(j['maturity_date']),
        notes: _str(j['notes']),
      );
}

class ProjectItem {
  const ProjectItem({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    required this.spent,
    this.budget,
    this.targetDate,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String status;
  final Money spent;
  final Money? budget;
  final String? targetDate;
  final String? startedAt;
  final String? completedAt;

  factory ProjectItem.fromJson(Map<String, dynamic> j) => ProjectItem(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        description: _str(j['description']),
        status: j['status']?.toString() ?? 'active',
        spent: Money.parse(j['spent']),
        budget: j['budget'] == null ? null : Money.parse(j['budget']),
        targetDate: _str(j['target_date']),
        startedAt: _str(j['started_at']),
        completedAt: _str(j['completed_at']),
      );
}
