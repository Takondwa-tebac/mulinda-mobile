import '../money/money_json.dart';

/// A write request recognised as a change to one of the offline-capable records.
class WriteMatch {
  const WriteMatch({required this.entity, required this.op, this.targetIds = const []});

  final String entity;

  /// create | update | delete
  final String op;
  final List<String> targetIds;
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

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// The records that can be changed offline.
const kEntityAdapters = <EntityAdapter>[TransactionAdapter(), GoalAdapter(), LoanAdapter()];

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
