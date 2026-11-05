import '../../../core/money/money.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.currentBalance,
    required this.isActive,
    this.pending = false,
    this.balanceEstimated = false,
  });

  final String id;
  final String name;
  final String type;
  final String currency;
  final Money currentBalance;
  final bool isActive;

  /// Created or edited on this phone and waiting to sync.
  final bool pending;

  /// The balance includes changes still waiting to sync, so it is an estimate.
  final bool balanceEstimated;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'wallet',
      currency: json['currency']?.toString() ?? 'MWK',
      currentBalance: Money.parse(json['current_balance']),
      isActive: json['is_active'] != false,
      pending: json['_pending'] == true,
      balanceEstimated: json['balance_estimated'] == true,
    );
  }
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.icon,
    this.color,
    this.isSpending = true,
  });

  final String id;
  final String name;
  final String kind; // expense | income

  /// A Material icon name and a `#RRGGBB` colour from the server; either may be missing.
  final String? icon;
  final String? color;

  /// False for categories that move money without spending it (e.g. "Moving
  /// my money" between your own accounts). Absent on older servers → true.
  final bool isSpending;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'expense',
      icon: json['icon']?.toString(),
      color: json['color']?.toString(),
      isSpending: json['is_spending'] != false,
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
    this.categoryId,
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
    this.pending = false,
    this.categoryIcon,
    this.categoryColor,
    this.categorisation,
    this.categoryIsSpending = true,
  });

  final String id;
  final String type; // income | expense | transfer
  final Money amount;
  final String? merchant;
  final String? categoryName;
  final String? categoryId;
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

  /// Saved on this phone and waiting to sync (made offline).
  final bool pending;

  /// The category's Material icon name and `#RRGGBB` colour, when sent.
  final String? categoryIcon;
  final String? categoryColor;

  /// Whether the category counts as spending (`category.is_spending`).
  final bool categoryIsSpending;

  /// An expense whose category is not spending (e.g. moving your own money):
  /// shown neutrally and left out of spending totals.
  bool get notSpending => type == 'expense' && categoryId != null && !categoryIsSpending;

  /// Counts toward money spent (expense in a spending category or none).
  bool get countsAsSpending => type == 'expense' && !notSpending;

  /// How the category was decided (absent from older API versions).
  final Categorisation? categorisation;

  /// The category is a guess or missing and the user should confirm it.
  /// Transfers never ask (moving money between your own accounts has no category).
  bool get needsCategory => type != 'transfer' && (categorisation?.needsAttention ?? false);

  /// The engine assigned a category it is not sure about ("Confirm category").
  bool get hasSuggestedCategory => categoryId != null && (categorisation?.isSuggested ?? false);

  /// Local time the transaction happened, or null when unknown.
  DateTime? get occurredLocal => occurredAt == null ? null : DateTime.tryParse(occurredAt!)?.toLocal();

  /// A copy with the category replaced (for optimistic updates). The new
  /// category is treated as confirmed by the user.
  Txn withCategory(Category? category, {Categorisation? categorisation}) => Txn(
    id: id,
    type: type,
    amount: amount,
    merchant: merchant,
    categoryName: category?.name,
    categoryId: category?.id,
    categoryIcon: category?.icon,
    categoryColor: category?.color,
    categoryIsSpending: category?.isSpending ?? true,
    categorisation:
        categorisation ??
        (category == null
            ? const Categorisation(status: 'uncategorised', needsAttention: true)
            : const Categorisation(status: 'confirmed', source: 'user', confidence: 1, needsAttention: false)),
    occurredAt: occurredAt,
    notes: notes,
    projectId: projectId,
    needsReview: needsReview,
    component: component,
    parentId: parentId,
    sender: sender,
    reference: reference,
    accountName: accountName,
    counterparty: counterparty,
    status: status,
    source: source,
    balanceAfter: balanceAfter,
    sourceSms: sourceSms,
    children: children,
    pending: pending,
  );

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
      categoryId: category?['id']?.toString(),
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
      children: rawChildren.map((e) => Txn.fromJson((e as Map).cast<String, dynamic>())).toList(),
      pending: json['_pending'] == true,
      categoryIcon: category?['icon']?.toString(),
      categoryColor: category?['color']?.toString(),
      categoryIsSpending: category?['is_spending'] != false,
      categorisation: json['categorisation'] is Map
          ? Categorisation.fromJson((json['categorisation'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

/// The `categorisation` block of a transaction: how its category was chosen.
class Categorisation {
  const Categorisation({required this.status, this.source, this.confidence, this.needsAttention = false});

  /// confirmed | auto | suggested | uncategorised
  final String status;

  /// user | user_rule | merchant_rule | keyword | sms_kind | legacy, or null.
  final String? source;
  final double? confidence;
  final bool needsAttention;

  bool get isConfirmed => status == 'confirmed';
  bool get isSuggested => status == 'suggested';
  bool get isUncategorised => status == 'uncategorised';

  factory Categorisation.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString() ?? 'uncategorised';
    return Categorisation(
      status: status,
      source: json['source']?.toString(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      // Older servers may omit the flag; derive it from the status then.
      needsAttention: json['needs_attention'] is bool
          ? json['needs_attention'] as bool
          : (status == 'suggested' || status == 'uncategorised'),
    );
  }
}

/// One page of the transactions list plus whether more pages exist.
class TxnPage {
  const TxnPage({required this.items, required this.page, required this.hasMore, this.total});

  final List<Txn> items;
  final int page;
  final bool hasMore;
  final int? total;
}

/// Filters for the transactions list (mirrors `GET /v1/transactions`).
class TxnQuery {
  const TxnQuery({
    this.search = '',
    this.type,
    this.categoryId,
    this.accountId,
    this.from,
    this.to,
    this.needsCategory = false,
  });

  final String search;

  /// income | expense, or null for both.
  final String? type;
  final String? categoryId;
  final String? accountId;

  /// Inclusive local dates.
  final DateTime? from;
  final DateTime? to;
  final bool needsCategory;

  static const none = TxnQuery();

  bool get isDefault =>
      search.trim().isEmpty &&
      type == null &&
      categoryId == null &&
      accountId == null &&
      from == null &&
      to == null &&
      !needsCategory;

  /// How many filters from the filter sheet (category, account, dates) are set.
  int get sheetFilterCount => [categoryId, accountId, from ?? to].where((e) => e != null).length;

  TxnQuery copyWith({
    String? search,
    String? Function()? type,
    String? Function()? categoryId,
    String? Function()? accountId,
    DateTime? Function()? from,
    DateTime? Function()? to,
    bool? needsCategory,
  }) => TxnQuery(
    search: search ?? this.search,
    type: type == null ? this.type : type(),
    categoryId: categoryId == null ? this.categoryId : categoryId(),
    accountId: accountId == null ? this.accountId : accountId(),
    from: from == null ? this.from : from(),
    to: to == null ? this.to : to(),
    needsCategory: needsCategory ?? this.needsCategory,
  );

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Query parameters per the API contract.
  Map<String, dynamic> toParams() => {
    if (search.trim().isNotEmpty) 'search': search.trim(),
    'type': ?type,
    'category_id': ?categoryId,
    'financial_account_id': ?accountId,
    if (from != null) 'from': _day(from!),
    if (to != null) 'to': '${_day(to!)}T23:59:59',
    if (needsCategory) 'needs_category': 1,
  };

  @override
  bool operator ==(Object other) =>
      other is TxnQuery &&
      other.search == search &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.accountId == accountId &&
      other.from == from &&
      other.to == to &&
      other.needsCategory == needsCategory;

  @override
  int get hashCode => Object.hash(search, type, categoryId, accountId, from, to, needsCategory);
}

/// The result of `POST /v1/transactions/{id}/category`.
class CategoryUpdate {
  const CategoryUpdate({required this.txn, required this.similarUpdated});

  final Txn txn;
  final int similarUpdated;
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
