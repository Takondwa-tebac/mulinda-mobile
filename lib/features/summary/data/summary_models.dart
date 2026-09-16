import '../../../core/money/money.dart';
import '../../activity/data/activity_models.dart';

/// A saved day's spending summary, as shown in the history screen.
class DailySummary {
  const DailySummary({
    required this.id,
    required this.date,
    required this.income,
    required this.expense,
    required this.net,
    required this.transactionCount,
    this.topCategory,
    this.topCategoryAmount,
  });

  final String id;
  final String date; // YYYY-MM-DD
  final Money income;
  final Money expense;
  final Money net;
  final int transactionCount;
  final String? topCategory;
  final Money? topCategoryAmount;

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    return DailySummary(
      id: json['id'].toString(),
      date: json['date']?.toString() ?? '',
      income: Money.parse(json['income']),
      expense: Money.parse(json['expense']),
      net: Money.parse(json['net']),
      transactionCount: json['transaction_count'] is int ? json['transaction_count'] as int : 0,
      topCategory: json['top_category']?.toString(),
      topCategoryAmount:
          json['top_category_amount'] is Map ? Money.parse(json['top_category_amount']) : null,
    );
  }
}

/// A daily summary with its associated transactions.
class DailySummaryWithTransactions {
  const DailySummaryWithTransactions({
    required this.id,
    required this.date,
    required this.income,
    required this.expense,
    required this.net,
    required this.transactionCount,
    this.topCategory,
    this.topCategoryAmount,
    required this.transactions,
  });

  final String id;
  final String date;
  final Money income;
  final Money expense;
  final Money net;
  final int transactionCount;
  final String? topCategory;
  final Money? topCategoryAmount;
  final List<Txn> transactions;

  factory DailySummaryWithTransactions.fromJson(Map<String, dynamic> json) {
    final txnsList = json['transactions'] as List?;
    return DailySummaryWithTransactions(
      id: json['id'].toString(),
      date: json['date']?.toString() ?? '',
      income: Money.parse(json['income']),
      expense: Money.parse(json['expense']),
      net: Money.parse(json['net']),
      transactionCount: json['transaction_count'] is int ? json['transaction_count'] as int : 0,
      topCategory: json['top_category']?.toString(),
      topCategoryAmount:
          json['top_category_amount'] is Map ? Money.parse(json['top_category_amount']) : null,
      transactions: txnsList
              ?.map((e) => Txn.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          [],
    );
  }
}
