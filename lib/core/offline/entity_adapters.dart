import '../money/money_json.dart';

/// A write request recognised as a change to one of the offline-capable records.
class WriteMatch {
  const WriteMatch({required this.entity, required this.op, this.targetIds = const [], this.parentId});

  final String entity;

  /// create | update | delete
  final String op;
  final List<String> targetIds;

  /// For a contribution or repayment: the goal or loan it belongs to.
  final String? parentId;
}

/// Finds a saved record by id (e.g. a category or account name) in the cached
/// reads, so locally built records can show the right labels.
typedef RecordLookup = Future<Map<String, dynamic>?> Function(String collectionPath, String id);

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// How one kind of record (transaction, goal, loan…) behaves offline: which
/// requests change it, what a record looks like before the server has seen it,
/// and how an edit shows up in lists and detail screens.
abstract class EntityAdapter {
  const EntityAdapter();

  String get entity;

  /// e.g. `/v1/transactions`
  String get collection;

  /// Recognise a write to this entity, or null.
  WriteMatch? matchWrite(String method, String path, dynamic body) {
    final m = method.toUpperCase();
    if (m == 'POST' && path == collection) {
      final id = body is Map ? body['id']?.toString() : null;
      return WriteMatch(entity: entity, op: 'create', targetIds: id == null ? const [] : [id]);
    }
    final id = detailId(path);
    if (id != null && (m == 'PUT' || m == 'PATCH')) {
      return WriteMatch(entity: entity, op: 'update', targetIds: [id]);
    }
    if (id != null && m == 'DELETE') {
      return WriteMatch(entity: entity, op: 'delete', targetIds: [id]);
    }
    return null;
  }

  bool isList(String path) => path == collection;

  /// The record id when [path] is exactly `<collection>/<id>`, else null.
  String? detailId(String path) {
    if (!path.startsWith('$collection/')) return null;
    final rest = path.substring(collection.length + 1);
    return _uuid.hasMatch(rest) ? rest : null;
  }

  /// The record a create will become, built on the device.
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup);

  /// [record] with an edit applied (also marks it as waiting to sync).
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body);

  /// Whether a local record belongs in a list requested with [query].
  bool matchesQuery(Map<String, dynamic> record, Map<String, dynamic> query) => true;

  /// The adapter for records nested under this one (goal → contributions), or null.
  ChildAdapter? get childAdapter => null;

  /// [record] after its children changed by [deltaMinor] (e.g. a goal's saved total).
  Map<String, dynamic> adjustForChildren(Map<String, dynamic> record, int deltaMinor) => record;

  static String now() => DateTime.now().toUtc().toIso8601String();

  static Map<String, dynamic> _pending(Map<String, dynamic> r) => {...r, '_pending': true, 'updated_at': now()};

  static Map<String, dynamic> pending(Map<String, dynamic> r) => _pending(r);
}

class TransactionAdapter extends EntityAdapter {
  const TransactionAdapter();

  @override
  String get entity => 'transaction';

  @override
  String get collection => '/v1/transactions';

  @override
  WriteMatch? matchWrite(String method, String path, dynamic body) {
    if (method.toUpperCase() == 'POST' && path == '$collection/bulk-delete') {
      final ids = body is Map && body['ids'] is List ? (body['ids'] as List).map((e) => e.toString()).toList() : <String>[];
      return WriteMatch(entity: entity, op: 'delete', targetIds: ids);
    }
    return super.matchWrite(method, path, body);
  }

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) async {
    final account = body['financial_account_id'] == null
        ? null
        : await lookup('/v1/accounts', body['financial_account_id'].toString());
    final category =
        body['category_id'] == null ? null : await lookup('/v1/categories', body['category_id'].toString());
    final currency = (body['currency'] ?? account?['currency'] ?? 'MWK').toString();
    final amount = (body['amount'] as num?)?.toDouble() ?? double.tryParse('${body['amount']}') ?? 0;
    final now = EntityAdapter.now();

    return {
      'id': body['id'],
      'financial_account_id': body['financial_account_id'],
      'project_id': body['project_id'],
      'category_id': body['category_id'],
      'parent_id': null,
      'type': body['type'] ?? 'expense',
      'component': null,
      'amount': moneyJson(amount, currency),
      'currency': currency,
      'merchant': body['merchant'],
      'counterparty': body['counterparty'],
      'reference': body['reference'],
      'balance_after': null,
      'occurred_at': body['occurred_at'] ?? now,
      'source': 'manual',
      'status': 'cleared',
      'needs_review': false,
      'sender': null,
      'notes': body['notes'],
      'category': category == null ? null : {'id': category['id'], 'name': category['name'], 'kind': category['kind']},
      'financial_account': account == null ? null : {'id': account['id'], 'name': account['name'], 'currency': currency},
      'children': <dynamic>[],
      'created_at': now,
      'updated_at': now,
      '_pending': true,
    };
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in const ['type', 'merchant', 'counterparty', 'reference', 'notes', 'occurred_at', 'project_id', 'status']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    if (body.containsKey('category_id')) {
      next['category_id'] = body['category_id'];
      // The name is not known without a lookup; drop the stale one rather than mislabel it.
      next['category'] = body['category_id'] == null ? null : (next['category'] is Map && (next['category'] as Map)['id'] == body['category_id'] ? next['category'] : null);
    }
    if (body['amount'] != null) {
      final currency = (record['currency'] ?? (record['amount'] is Map ? (record['amount'] as Map)['currency'] : null) ?? 'MWK').toString();
      next['amount'] = moneyJson((body['amount'] as num).toDouble(), currency);
    }
    return EntityAdapter.pending(next);
  }

  @override
  bool matchesQuery(Map<String, dynamic> record, Map<String, dynamic> query) {
    for (final key in const ['financial_account_id', 'project_id', 'category_id', 'type']) {
      final wanted = query[key];
      if (wanted != null && '$wanted'.isNotEmpty && record[key]?.toString() != '$wanted') return false;
    }
    final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
    return page <= 1; // new records belong on the first page
  }
}

class GoalAdapter extends EntityAdapter {
  const GoalAdapter();

  @override
  String get entity => 'goal';

  @override
  ChildAdapter get childAdapter => const GoalContributionAdapter();

  @override
  Map<String, dynamic> adjustForChildren(Map<String, dynamic> record, int deltaMinor) {
    if (deltaMinor == 0) return record;
    final current = record['current'];
    final currency = (record['currency'] ?? (current is Map ? current['currency'] : null) ?? 'MWK').toString();
    final minor = (_minor(current) + deltaMinor).clamp(0, 1 << 52);
    return {...record, 'current': moneyJson(minor / 100, currency), '_pending': true};
  }

  @override
  String get collection => '/v1/goals';

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) async {
    final currency = (body['currency'] ?? 'MWK').toString();
    final now = EntityAdapter.now();
    return {
      'id': body['id'],
      'name': body['name'],
      'type': body['type'] ?? 'custom',
      'target': moneyJson(_num(body['target']), currency),
      'current': moneyJson(0, currency),
      'currency': currency,
      'target_date': body['target_date'],
      'monthly_contribution': body['monthly_contribution'] == null ? null : moneyJson(_num(body['monthly_contribution']), currency),
      'status': 'active',
      'progress': <String, dynamic>{},
      'contributions': <dynamic>[],
      'updated_at': now,
      '_pending': true,
    };
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in const ['name', 'type', 'target_date', 'status']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    final currency = (record['currency'] ?? 'MWK').toString();
    if (body['target'] != null) next['target'] = moneyJson(_num(body['target']), currency);
    if (body.containsKey('monthly_contribution')) {
      next['monthly_contribution'] = body['monthly_contribution'] == null ? null : moneyJson(_num(body['monthly_contribution']), currency);
    }
    return EntityAdapter.pending(next);
  }
}

class LoanAdapter extends EntityAdapter {
  const LoanAdapter();

  @override
  String get entity => 'loan';

  @override
  ChildAdapter get childAdapter => const LoanRepaymentAdapter();

  /// A repayment reduces what is still owed (shown from the loan's progress).
  @override
  Map<String, dynamic> adjustForChildren(Map<String, dynamic> record, int deltaMinor) {
    if (deltaMinor == 0) return record;
    final progress = record['progress'] is Map ? (record['progress'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final currency = (record['currency'] ?? 'MWK').toString();
    final outstanding = (_minor(progress['outstanding']) - deltaMinor).clamp(0, 1 << 52);
    return {...record, 'progress': {...progress, 'outstanding': moneyJson(outstanding / 100, currency)}, '_pending': true};
  }

  @override
  String get collection => '/v1/loans';

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) async {
    final currency = (body['currency'] ?? 'MWK').toString();
    final principal = moneyJson(_num(body['principal']), currency);
    final now = EntityAdapter.now();
    return {
      'id': body['id'],
      'name': body['name'],
      'lender': body['lender'],
      'principal': principal,
      'currency': currency,
      'annual_interest_rate': body['annual_interest_rate'] ?? 0,
      'interest_type': body['interest_type'] ?? 'reducing_balance',
      'term_months': body['term_months'] ?? 12,
      'status': body['status'] ?? 'active',
      'disbursed_at': body['disbursed_at'],
      'first_payment_date': body['first_payment_date'],
      // The schedule is computed by the server once the loan syncs.
      'schedule': null,
      'progress': {'outstanding': principal},
      'repayments': <dynamic>[],
      'created_at': now,
      'updated_at': now,
      '_pending': true,
    };
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in const [
      'name', 'lender', 'annual_interest_rate', 'interest_type', 'term_months', 'status', 'disbursed_at', 'first_payment_date',
    ]) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    if (body['principal'] != null) {
      next['principal'] = moneyJson(_num(body['principal']), (record['currency'] ?? 'MWK').toString());
    }
    return EntityAdapter.pending(next);
  }
}

/// How much a transaction moves its account's balance, in minor units:
/// income adds, expense subtracts, anything else (transfers) leaves it alone.
int signedAmountMinor(String? type, int amountMinor) => switch (type) {
      'income' => amountMinor,
      'expense' => -amountMinor,
      _ => 0,
    };

/// A financial account (wallet, bank, mobile money…). Besides being created,
/// edited and deleted offline, its balance is *estimated* from transactions that
/// are still waiting to sync (see [adjustBalance]).
class AccountAdapter extends EntityAdapter {
  const AccountAdapter();

  @override
  String get entity => 'account';

  @override
  String get collection => '/v1/accounts';

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) async {
    final currency = (body['currency'] ?? 'MWK').toString();
    final opening = moneyJson(_num(body['opening_balance']), currency);
    final now = EntityAdapter.now();
    return {
      'id': body['id'],
      'name': body['name'],
      'type': body['type'] ?? 'wallet',
      'provider_id': body['provider_id'],
      'account_reference': body['account_reference'],
      'currency': currency,
      'opening_balance': opening,
      'current_balance': opening,
      'is_active': body['is_active'] ?? true,
      'created_at': now,
      'updated_at': now,
      '_pending': true,
    };
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in const ['name', 'type', 'account_reference', 'is_active', 'provider_id']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    return EntityAdapter.pending(next);
  }

  /// [record] with its balance moved by [deltaMinor] and flagged as an estimate.
  Map<String, dynamic> adjustBalance(Map<String, dynamic> record, int deltaMinor) {
    if (deltaMinor == 0) return record;
    final currency = (record['currency'] ?? 'MWK').toString();
    final minor = _minor(record['current_balance']) + deltaMinor;
    return {...record, 'current_balance': moneyJson(minor / 100, currency), 'balance_estimated': true};
  }
}

class BudgetAdapter extends EntityAdapter {
  const BudgetAdapter();

  @override
  String get entity => 'budget';

  @override
  String get collection => '/v1/budgets';

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) async {
    final currency = (body['currency'] ?? 'MWK').toString();
    final category = body['category_id'] == null ? null : await lookup('/v1/categories', body['category_id'].toString());
    final limit = moneyJson(_num(body['limit']), currency);
    return {
      'id': body['id'],
      'name': body['name'] ?? category?['name'],
      'category_id': body['category_id'],
      'category': category == null ? null : {'id': category['id'], 'name': category['name'], 'kind': category['kind']},
      'period': body['period'] ?? 'monthly',
      'limit': limit,
      'currency': currency,
      'alert_threshold': body['alert_threshold'] ?? 0.8,
      'is_active': body['is_active'] ?? true,
      // Spending is worked out by the server once it syncs.
      'status': {'limit': limit, 'spent': moneyJson(0, currency), 'percentage': 0, 'is_exceeded': false, 'category': category?['name']},
      'updated_at': EntityAdapter.now(),
      '_pending': true,
    };
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in const ['name', 'category_id', 'period', 'alert_threshold', 'is_active']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    if (body['limit'] != null) {
      final currency = (record['currency'] ?? 'MWK').toString();
      final limit = moneyJson(_num(body['limit']), currency);
      next['limit'] = limit;
      if (next['status'] is Map) next['status'] = {...(next['status'] as Map).cast<String, dynamic>(), 'limit': limit};
    }
    return EntityAdapter.pending(next);
  }
}

class InvestmentAdapter extends EntityAdapter {
  const InvestmentAdapter();

  @override
  String get entity => 'investment';

  @override
  String get collection => '/v1/investments';

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) async {
    final currency = (body['currency'] ?? 'MWK').toString();
    final invested = _num(body['amount_invested']);
    final value = body['current_value'] == null ? invested : _num(body['current_value']);
    return {
      'id': body['id'],
      'name': body['name'],
      'type': body['type'] ?? 'other',
      'status': body['status'] ?? 'active',
      'currency': currency,
      'amount_invested': moneyJson(invested, currency),
      'current_value': moneyJson(value, currency),
      'gain': moneyJson(value - invested, currency),
      'gain_percent': invested > 0 ? (value - invested) / invested : null,
      // Interest accrued so far is worked out by the server once it syncs.
      'value_source': body['current_value'] == null ? 'invested' : 'recorded',
      'accrual': null,
      'expected_annual_return': body['expected_annual_return'],
      'interest_period': body['interest_period'],
      'started_at': body['started_at'],
      'maturity_date': body['maturity_date'],
      'notes': body['notes'],
      'created_at': EntityAdapter.now(),
      'updated_at': EntityAdapter.now(),
      '_pending': true,
    };
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in const ['name', 'type', 'status', 'expected_annual_return', 'interest_period', 'started_at', 'maturity_date', 'notes']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    final currency = (record['currency'] ?? 'MWK').toString();
    if (body['amount_invested'] != null) next['amount_invested'] = moneyJson(_num(body['amount_invested']), currency);
    if (body.containsKey('current_value') && body['current_value'] != null) {
      next['current_value'] = moneyJson(_num(body['current_value']), currency);
      next['value_source'] = 'recorded';
    }
    // Keep the gain consistent with whatever is now shown.
    final invested = _minor(next['amount_invested']);
    final value = _minor(next['current_value']);
    next['gain'] = {'minor_units': value - invested, 'currency': currency, 'amount': (value - invested) / 100, 'formatted': formatMoney((value - invested) / 100, currency)};
    return EntityAdapter.pending(next);
  }
}

class ProjectAdapter extends EntityAdapter {
  const ProjectAdapter();

  @override
  String get entity => 'project';

  @override
  String get collection => '/v1/projects';

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) async {
    final currency = (body['currency'] ?? 'MWK').toString();
    final budget = body['budget'] == null ? null : moneyJson(_num(body['budget']), currency);
    return {
      'id': body['id'],
      'name': body['name'],
      'description': body['description'],
      'status': body['status'] ?? 'active',
      'currency': currency,
      'budget': budget,
      'spent': moneyJson(0, currency),
      'remaining': budget,
      'completion_percentage': null,
      'transaction_count': 0,
      'target_date': body['target_date'],
      'started_at': body['started_at'],
      'completed_at': body['completed_at'],
      'created_at': EntityAdapter.now(),
      'updated_at': EntityAdapter.now(),
      '_pending': true,
    };
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in const ['name', 'description', 'status', 'target_date', 'started_at', 'completed_at']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    if (body.containsKey('budget')) {
      final currency = (record['currency'] ?? 'MWK').toString();
      next['budget'] = body['budget'] == null ? null : moneyJson(_num(body['budget']), currency);
    }
    return EntityAdapter.pending(next);
  }
}

/// Records nested under a goal or loan (contributions, repayments). They are read
/// as part of the parent's detail, so their queued changes are layered into that
/// detail and into the parent's totals rather than into a list of their own.
abstract class ChildAdapter extends EntityAdapter {
  const ChildAdapter();

  /// `/v1/goals`
  String get parentCollection;

  /// The key holding the children in the parent's detail JSON.
  String get childKey;

  /// `contributions` / `repayments`
  String get segment;

  /// The date field name (`contributed_at` / `paid_at`).
  String get dateKey;

  /// The foreign key (`goal_id` / `loan_id`).
  String get parentKey;

  @override
  String get collection => parentCollection;

  @override
  bool isList(String path) => false;

  @override
  String? detailId(String path) => null;

  RegExp get _writePath =>
      RegExp('^${RegExp.escape(parentCollection)}/($_uuidPattern)/$segment(?:/($_uuidPattern))?' r'$');

  @override
  WriteMatch? matchWrite(String method, String path, dynamic body) {
    final m = _writePath.firstMatch(path);
    if (m == null) return null;
    final parent = m.group(1)!;
    final child = m.group(2);
    final verb = method.toUpperCase();
    if (child == null && verb == 'POST') {
      final id = body is Map ? body['id']?.toString() : null;
      return WriteMatch(entity: entity, op: 'create', targetIds: id == null ? const [] : [id], parentId: parent);
    }
    if (child != null && (verb == 'PUT' || verb == 'PATCH')) {
      return WriteMatch(entity: entity, op: 'update', targetIds: [child], parentId: parent);
    }
    if (child != null && verb == 'DELETE') {
      return WriteMatch(entity: entity, op: 'delete', targetIds: [child], parentId: parent);
    }
    return null;
  }

  /// The amount, in minor units, of a stored child record.
  int amountMinor(Map<String, dynamic> record) => _minor(record['amount']);

  /// How the parent's totals move when this change replays.
  int deltaMinor(String op, Map<String, dynamic> body, Map<String, dynamic>? existing) {
    final newMinor = body['amount'] == null ? null : (_num(body['amount']) * 100).round();
    switch (op) {
      case 'create':
        return newMinor ?? 0;
      case 'update':
        return existing == null || newMinor == null ? 0 : newMinor - amountMinor(existing);
      case 'delete':
        return existing == null ? 0 : -amountMinor(existing);
    }
    return 0;
  }

  @override
  Map<String, dynamic> applyPatch(Map<String, dynamic> record, Map<String, dynamic> body) {
    final next = {...record};
    for (final key in [dateKey, 'note', 'financial_account_id']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    if (body['amount'] != null) {
      next['amount'] = moneyJson(_num(body['amount']), (record['currency'] ?? 'MWK').toString());
    }
    return EntityAdapter.pending(next);
  }

  Future<Map<String, dynamic>> _build(Map<String, dynamic> body, String parentId, RecordLookup lookup) async {
    final parent = await lookup(parentCollection, parentId);
    final currency = (parent?['currency'] ?? 'MWK').toString();
    final today = DateTime.now().toIso8601String().split('T').first;
    return {
      'id': body['id'],
      parentKey: parentId,
      'financial_account_id': body['financial_account_id'],
      'transaction_id': null,
      'amount': moneyJson(_num(body['amount']), currency),
      'currency': currency,
      dateKey: body[dateKey] ?? today,
      'note': body['note'],
      'financial_account': null,
      'transaction': null,
      'created_at': EntityAdapter.now(),
      'updated_at': EntityAdapter.now(),
      '_pending': true,
    };
  }

  @override
  Future<Map<String, dynamic>> buildRecord(Map<String, dynamic> body, RecordLookup lookup) =>
      _build(body, body['_parent_id']?.toString() ?? '', lookup);
}

class GoalContributionAdapter extends ChildAdapter {
  const GoalContributionAdapter();

  @override
  String get entity => 'goal_contribution';
  @override
  String get parentCollection => '/v1/goals';
  @override
  String get childKey => 'contributions';
  @override
  String get segment => 'contributions';
  @override
  String get dateKey => 'contributed_at';
  @override
  String get parentKey => 'goal_id';
}

class LoanRepaymentAdapter extends ChildAdapter {
  const LoanRepaymentAdapter();

  @override
  String get entity => 'loan_repayment';
  @override
  String get parentCollection => '/v1/loans';
  @override
  String get childKey => 'repayments';
  @override
  String get segment => 'repayments';
  @override
  String get dateKey => 'paid_at';
  @override
  String get parentKey => 'loan_id';
}

const _uuidPattern = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

int _minor(dynamic money) => money is Map ? ((money['minor_units'] as num?)?.toInt() ?? 0) : 0;

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// The records that can be changed offline.
const kEntityAdapters = <EntityAdapter>[
  AccountAdapter(),
  TransactionAdapter(),
  GoalAdapter(),
  LoanAdapter(),
  BudgetAdapter(),
  InvestmentAdapter(),
  ProjectAdapter(),
  GoalContributionAdapter(),
  LoanRepaymentAdapter(),
];

WriteMatch? matchWrite(String method, String path, dynamic body) {
  for (final a in kEntityAdapters) {
    final m = a.matchWrite(method, path, body);
    if (m != null) return m;
  }
  return null;
}

EntityAdapter? adapterFor(String entity) {
  for (final a in kEntityAdapters) {
    if (a.entity == entity) return a;
  }
  return null;
}
