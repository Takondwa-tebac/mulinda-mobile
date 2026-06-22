import '../../../core/money/money.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.currentBalance,
    required this.isActive,
  });

  final String id;
  final String name;
  final String type;
  final String currency;
  final Money currentBalance;
  final bool isActive;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'wallet',
      currency: json['currency']?.toString() ?? 'MWK',
      currentBalance: Money.parse(json['current_balance']),
      isActive: json['is_active'] != false,
    );
  }
}

class Category {
  const Category({required this.id, required this.name, required this.kind});

  final String id;
  final String name;
  final String kind; // expense | income

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'expense',
    );
  }
}

class Txn {
  const Txn({
    required this.id,
    required this.type,
    required this.amount,
    this.merchant,
    this.categoryName,
    this.occurredAt,
    this.notes,
  });

  final String id;
  final String type; // income | expense
  final Money amount;
  final String? merchant;
  final String? categoryName;
  final String? occurredAt;
  final String? notes;

  bool get isIncome => type == 'income';

  /// Date portion of the ISO occurred_at, for display.
  String get date => (occurredAt ?? '').split('T').first;

  factory Txn.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] as Map?)?.cast<String, dynamic>();
    return Txn(
      id: json['id'].toString(),
      type: json['type']?.toString() ?? 'expense',
      amount: Money.parse(json['amount']),
      merchant: json['merchant']?.toString(),
      categoryName: category?['name']?.toString(),
      occurredAt: json['occurred_at']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}
