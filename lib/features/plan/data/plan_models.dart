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

/// Interest accrued so far on a term investment, computed by the API so the
/// list card and the detail screen always agree.
class InvestmentAccrual {
  const InvestmentAccrual({
    required this.interestSoFar,
    required this.estimatedValue,
    required this.totalInterest,
    required this.maturityValue,
    required this.progress,
    required this.daysToMaturity,
    required this.matured,
  });

  final Money interestSoFar;
  final Money estimatedValue;
  final Money totalInterest;
  final Money maturityValue;
  final double progress;
  final int daysToMaturity;
  final bool matured;

  factory InvestmentAccrual.fromJson(Map<String, dynamic> j) => InvestmentAccrual(
        interestSoFar: Money.parse(j['interest_so_far']),
        estimatedValue: Money.parse(j['estimated_value']),
        totalInterest: Money.parse(j['total_interest']),
        maturityValue: Money.parse(j['maturity_value']),
        progress: _num(j['progress']) ?? 0,
        daysToMaturity: (j['days_to_maturity'] as num?)?.toInt() ?? 0,
        matured: j['matured'] == true,
      );
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
    this.interestPeriod,
    this.startedAt,
    this.maturityDate,
    this.notes,
    this.accrual,
    this.valueSource = 'recorded',
  });

  final String id;
  final String name;
  final String type;
  final String status;
  final Money amountInvested;
  final Money value;
  final Money gain;
  final double? expectedReturn;
  final String? interestPeriod;
  final String? startedAt;
  final String? maturityDate;
  final String? notes;

  /// Interest accrued so far / at maturity; null when no term or rate is set.
  final InvestmentAccrual? accrual;

  /// recorded | estimated | invested — how [value] was arrived at.
  final String valueSource;

  /// True when [value] is the interest-accrued estimate, not a recorded value.
  bool get isEstimated => valueSource == 'estimated';

  factory InvestmentItem.fromJson(Map<String, dynamic> j) => InvestmentItem(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        type: j['type']?.toString() ?? 'other',
        status: j['status']?.toString() ?? 'active',
        amountInvested: Money.parse(j['amount_invested']),
        value: Money.parse(j['current_value']),
        gain: Money.parse(j['gain']),
        expectedReturn: _num(j['expected_annual_return']),
        interestPeriod: _str(j['interest_period']),
        startedAt: _str(j['started_at']),
        maturityDate: _str(j['maturity_date']),
        notes: _str(j['notes']),
        accrual: j['accrual'] is Map
            ? InvestmentAccrual.fromJson((j['accrual'] as Map).cast<String, dynamic>())
            : null,
        valueSource: j['value_source']?.toString() ?? 'recorded',
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
    this.completionPercentage,
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
  final double? completionPercentage;

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
        completionPercentage: _num(j['completion_percentage']),
      );
}

class GoalContribution {
  const GoalContribution({
    required this.id,
    required this.goalId,
    required this.amount,
    required this.currency,
    this.financialAccountId,
    this.transactionId,
    this.contributedAt,
    this.note,
    this.financialAccount,
    this.transaction,
  });

  final String id;
  final String goalId;
  final Money amount;
  final String currency;
  final String? financialAccountId;
  final String? transactionId;
  final String? contributedAt;
  final String? note;
  final Map<String, dynamic>? financialAccount;
  final Map<String, dynamic>? transaction;

  factory GoalContribution.fromJson(Map<String, dynamic> j) => GoalContribution(
        id: j['id'].toString(),
        goalId: j['goal_id'].toString(),
        amount: Money.parse(j['amount']),
        currency: j['currency']?.toString() ?? 'MWK',
        financialAccountId: _str(j['financial_account_id']),
        transactionId: _str(j['transaction_id']),
        contributedAt: _str(j['contributed_at']),
        note: _str(j['note']),
        financialAccount: j['financial_account'] as Map<String, dynamic>?,
        transaction: j['transaction'] as Map<String, dynamic>?,
  );
}

class LoanRepayment {
  const LoanRepayment({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.currency,
    this.financialAccountId,
    this.transactionId,
    this.paidAt,
    this.note,
    this.financialAccount,
    this.transaction,
  });

  final String id;
  final String loanId;
  final Money amount;
  final String currency;
  final String? financialAccountId;
  final String? transactionId;
  final String? paidAt;
  final String? note;
  final Map<String, dynamic>? financialAccount;
  final Map<String, dynamic>? transaction;

  factory LoanRepayment.fromJson(Map<String, dynamic> j) => LoanRepayment(
        id: j['id'].toString(),
        loanId: j['loan_id'].toString(),
        amount: Money.parse(j['amount']),
        currency: j['currency']?.toString() ?? 'MWK',
        financialAccountId: _str(j['financial_account_id']),
        transactionId: _str(j['transaction_id']),
        paidAt: _str(j['paid_at']),
        note: _str(j['note']),
        financialAccount: j['financial_account'] as Map<String, dynamic>?,
        transaction: j['transaction'] as Map<String, dynamic>?,
  );
}
