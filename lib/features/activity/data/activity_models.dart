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
    this.projectId,
    this.needsReview = false,
    this.component,
    this.parentId,
    this.sender,
    this.reference,
    this.accountName,
    this.counterparty,
    this.status,
    this.source,
    this.balanceAfter,
    this.sourceSms,
    this.children = const [],
  });

  final String id;
  final String type; // income | expense | transfer
  final Money amount;
  final String? merchant;
  final String? categoryName;
  final String? occurredAt;
  final String? notes;
  final String? projectId;

  /// Auto-recorded from an SMS and awaiting the user's confirmation.
  final bool needsReview;

  /// null for a standalone/principal row; otherwise principal | fee | levy | tax.
  final String? component;
  final String? parentId;

  /// The SMS sender id this row was parsed from (e.g. AIRTELMONEY).
  final String? sender;
  final String? reference;
  final String? accountName;
  final String? counterparty;
  final String? status; // pending | cleared
  final String? source; // manual | sms | scan | import
  final Money? balanceAfter;

  /// The raw captured SMS, present only on auto-recorded transactions (detail view).
  final SourceSms? sourceSms;

  /// Fee/levy line items split from this principal, shown nested under it.
  final List<Txn> children;

  bool get isIncome => type == 'income';
  bool get isFee => component == 'fee';
  bool get isLevy => component == 'levy';
  bool get fromSms => sender != null && sender!.isNotEmpty;
  bool get isAutoCaptured => source == 'sms';

  /// Date portion of the ISO occurred_at, for display.
  String get date => (occurredAt ?? '').split('T').first;

  factory Txn.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] as Map?)?.cast<String, dynamic>();
    final account = (json['financial_account'] as Map?)?.cast<String, dynamic>();
    final rawChildren = (json['children'] as List?) ?? const [];
    final sms = (json['source_sms'] as Map?)?.cast<String, dynamic>();
    return Txn(
      id: json['id'].toString(),
      type: json['type']?.toString() ?? 'expense',
      amount: Money.parse(json['amount']),
      merchant: json['merchant']?.toString(),
      categoryName: category?['name']?.toString(),
      occurredAt: json['occurred_at']?.toString(),
      notes: json['notes']?.toString(),
      projectId: json['project_id']?.toString(),
      needsReview: json['needs_review'] == true,
      component: json['component']?.toString(),
      parentId: json['parent_id']?.toString(),
      sender: json['sender']?.toString(),
      reference: json['reference']?.toString(),
      accountName: account?['name']?.toString(),
      counterparty: json['counterparty']?.toString(),
      status: json['status']?.toString(),
      source: json['source']?.toString(),
      balanceAfter: json['balance_after'] is Map ? Money.parse(json['balance_after']) : null,
      sourceSms: sms != null ? SourceSms.fromJson(sms) : null,
      children: rawChildren
          .map((e) => Txn.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// The raw SMS an auto-captured transaction was parsed from.
class SourceSms {
  const SourceSms({this.sender, required this.body, this.receivedAt, this.confidence, this.parsed});

  final String? sender;
  final String body;
  final String? receivedAt;
  final num? confidence;
  final Map<String, dynamic>? parsed;

  factory SourceSms.fromJson(Map<String, dynamic> json) => SourceSms(
        sender: json['sender']?.toString(),
        body: json['body']?.toString() ?? '',
        receivedAt: json['received_at']?.toString(),
        confidence: json['confidence'] as num?,
        parsed: (json['parsed'] as Map?)?.cast<String, dynamic>(),
      );
}
