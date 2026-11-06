Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
String? _str(dynamic v) => (v == null || v.toString().isEmpty) ? null : v.toString();

/// Who did it (null for system events).
class AuditActor {
  const AuditActor({this.id, this.name, this.email, this.role});

  final String? id;
  final String? name;
  final String? email;
  final String? role;

  String get display => name ?? email ?? id ?? '';

  static AuditActor? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return AuditActor(id: _str(j['id']), name: _str(j['name']), email: _str(j['email']), role: _str(j['role']));
  }
}

/// What it was done to.
class AuditSubject {
  const AuditSubject({this.type, this.id, this.label});

  final String? type;
  final String? id;
  final String? label;

  String get display => [type, label ?? id].whereType<String>().join(' · ');

  factory AuditSubject.fromJson(dynamic v) {
    final j = _map(v);
    return AuditSubject(type: _str(j['type']), id: _str(j['id']), label: _str(j['label']));
  }
}

/// One row of GET /admin/audits.
class AuditItem {
  const AuditItem({
    required this.id,
    required this.event,
    required this.icon,
    this.actor,
    this.subject = const AuditSubject(),
    this.platform,
    this.createdAt,
  });

  final String id;
  final String event;

  /// created|updated|deleted|restored|login|login_failed|logout|export|role|
  /// subscription|credit|other
  final String icon;
  final AuditActor? actor;
  final AuditSubject subject;
  final String? platform;
  final DateTime? createdAt;

  factory AuditItem.fromJson(Map<String, dynamic> j) => AuditItem(
    id: j['id'].toString(),
    event: j['event']?.toString() ?? '',
    icon: j['icon']?.toString() ?? 'other',
    actor: AuditActor.fromJson(j['actor']),
    subject: AuditSubject.fromJson(j['subject']),
    platform: _str(j['platform']),
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
  );
}

/// A page of audits.
class AuditPage {
  const AuditPage({required this.items, required this.page, required this.hasMore});

  final List<AuditItem> items;
  final int page;
  final bool hasMore;

  factory AuditPage.fromJson(Map<String, dynamic> body, {int page = 1}) {
    final list = (body['data'] as List?) ?? const [];
    final meta = _map(body['meta']);
    final current = (meta['current_page'] as num?)?.toInt() ?? page;
    final last = (meta['last_page'] as num?)?.toInt() ?? current;
    return AuditPage(
      items: list.whereType<Map>().map((e) => AuditItem.fromJson(e.cast<String, dynamic>())).toList(),
      page: current,
      hasMore: current < last,
    );
  }
}

/// One changed field (old → new), already formatted by the server.
class AuditChange {
  const AuditChange({required this.field, required this.label, this.oldValue, this.newValue});

  final String field;
  final String label;
  final String? oldValue;
  final String? newValue;

  factory AuditChange.fromJson(Map<String, dynamic> j) => AuditChange(
    field: j['field']?.toString() ?? '',
    label: _str(j['label']) ?? j['field']?.toString() ?? '',
    oldValue: _str(j['old']),
    newValue: _str(j['new']),
  );
}

/// GET /admin/audits/{id}: the audit split into sections.
class AuditDetail {
  const AuditDetail({
    required this.id,
    required this.event,
    required this.icon,
    this.createdAt,
    this.actor,
    this.action = const {},
    this.changes = const [],
    this.device = const {},
    this.network = const {},
    this.request = const {},
    this.meta = const {},
  });

  final String id;
  final String event;
  final String icon;
  final DateTime? createdAt;
  final AuditActor? actor;
  final Map<String, dynamic> action;
  final List<AuditChange> changes;
  final Map<String, dynamic> device;
  final Map<String, dynamic> network;
  final Map<String, dynamic> request;
  final Map<String, dynamic> meta;

  factory AuditDetail.fromJson(Map<String, dynamic> j) {
    final s = _map(j['sections']);
    return AuditDetail(
      id: j['id'].toString(),
      event: j['event']?.toString() ?? '',
      icon: j['icon']?.toString() ?? 'other',
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
      actor: AuditActor.fromJson(s['actor']),
      action: _map(s['action']),
      changes: ((s['changes'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AuditChange.fromJson(e.cast<String, dynamic>()))
          .toList(),
      device: _map(s['device']),
      network: _map(s['network']),
      request: _map(s['request']),
      meta: _map(s['meta']),
    );
  }
}

/// Choices for the filter sheet (GET /admin/audits/filters).
class AuditFilterOptions {
  const AuditFilterOptions({this.events = const [], this.models = const []});

  final List<String> events;

  /// (type, label)
  final List<(String, String)> models;

  factory AuditFilterOptions.fromJson(Map<String, dynamic> j) => AuditFilterOptions(
    events: ((j['events'] as List?) ?? const []).map((e) => e.toString()).toList(),
    models: ((j['models'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => (e['type'].toString(), (e['label'] ?? e['type']).toString()))
        .toList(),
  );
}

/// Filters for the audit list and exports (mirrors the API's query names).
class AuditQuery {
  const AuditQuery({this.q = '', this.event, this.model, this.platform, this.actor, this.from, this.to});

  final String q;
  final String? event;
  final String? model;
  final String? platform;
  final String? actor;
  final DateTime? from;
  final DateTime? to;

  static const none = AuditQuery();

  int get count => [event, model, platform, actor, from ?? to].where((e) => e != null).length;

  static String _day(DateTime d) => d.toIso8601String().split('T').first;

  Map<String, dynamic> toParams() => {
    if (q.trim().isNotEmpty) 'q': q.trim(),
    'event': ?event,
    'model': ?model,
    'platform': ?platform,
    'actor': ?actor,
    if (from != null) 'from': _day(from!),
    if (to != null) 'to': _day(to!),
  };

  @override
  bool operator ==(Object other) =>
      other is AuditQuery &&
      other.q == q &&
      other.event == event &&
      other.model == model &&
      other.platform == platform &&
      other.actor == actor &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(q, event, model, platform, actor, from, to);
}

/// An audit export job.
class AuditExport {
  const AuditExport({
    required this.id,
    required this.status,
    required this.format,
    this.rowCount,
    this.truncated = false,
    this.downloadUrl,
  });

  final String id;

  /// queued | processing | ready | failed
  final String status;
  final String format;
  final int? rowCount;
  final bool truncated;
  final String? downloadUrl;

  bool get isDone => status == 'ready' || status == 'failed';
  bool get isReady => status == 'ready' && downloadUrl != null;

  factory AuditExport.fromJson(Map<String, dynamic> j) => AuditExport(
    id: j['id'].toString(),
    status: j['status']?.toString() ?? 'queued',
    format: j['format']?.toString() ?? 'csv',
    rowCount: (j['row_count'] as num?)?.toInt(),
    truncated: j['truncated'] == true,
    downloadUrl: _str(j['download_url']),
  );
}
