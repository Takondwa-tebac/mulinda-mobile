/// The active plan on an admin user record (GET /admin/users/{id}).
class AdminSubscription {
  const AdminSubscription({this.planLabel, this.source, this.endsAt, this.isTrial = false});

  /// Plan name as the server labels it ("Monthly", "Day Pass"…).
  final String? planLabel;

  /// payment | credit | trial
  final String? source;
  final DateTime? endsAt;
  final bool isTrial;
}

/// One user as the admin user detail endpoint returns it. Only fields the API
/// sends; anything missing stays null.
class AdminUser {
  const AdminUser({
    required this.id,
    this.fullName,
    this.firstName,
    this.username,
    this.email,
    this.phone,
    this.avatarUrl,
    this.incomeBracket,
    this.smsCaptureCount = 0,
    this.roles = const [],
    this.screenshotsAllowed = false,
    this.subscription,
    this.createdAt,
    this.lastActiveAt,
  });

  final String id;
  final String? fullName;
  final String? firstName;
  final String? username;
  final String? email;
  final String? phone;
  final String? avatarUrl;

  /// low | lower_middle | middle | upper_middle | upper
  final String? incomeBracket;
  final int smsCaptureCount;
  final List<String> roles;
  final bool screenshotsAllowed;

  /// Null when the person has no active plan (free).
  final AdminSubscription? subscription;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;

  bool get isSubscribed => subscription != null;
  bool get isSuperAdmin => roles.contains('super-admin');
  bool get isAdmin => roles.contains('admin') || isSuperAdmin;

  /// Full name, else username, else email.
  String get displayName => _first([fullName, username, email]) ?? '';

  /// The first name for sentences ("Allow screenshots for Chisomo?").
  String get shortName {
    final first = firstName?.trim() ?? '';
    if (first.isNotEmpty) return first;
    final full = fullName?.trim() ?? '';
    if (full.isNotEmpty) return full.split(RegExp(r'\s+')).first;
    return username ?? email ?? '';
  }

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory AdminUser.fromJson(Map<String, dynamic> j) {
    final sub = j['subscription'];
    final active = sub is Map && sub['active'] == true;
    return AdminUser(
      id: j['id'].toString(),
      fullName: _str(j['full_name']),
      firstName: _str(j['first_name']),
      username: _str(j['username']),
      email: _str(j['email']),
      phone: _str(j['phone_number']),
      avatarUrl: _str(j['avatar_url']),
      incomeBracket: _str(j['declared_income_bracket']),
      smsCaptureCount: (j['sms_capture_count'] as num?)?.toInt() ?? 0,
      roles: ((j['roles'] as List?) ?? const [])
          .map((r) => r is Map ? (r['name']?.toString() ?? '') : r.toString())
          .where((r) => r.isNotEmpty)
          .toList(),
      screenshotsAllowed: j['screenshots_allowed'] == true,
      subscription: active
          ? AdminSubscription(
              planLabel: _str(sub['plan_label']),
              source: _str(sub['source']),
              endsAt: _date(sub['ends_at']),
              isTrial: sub['is_trial'] == true,
            )
          : null,
      createdAt: _date(j['created_at']),
      lastActiveAt: _date(j['last_active_at']),
    );
  }
}

String? _str(dynamic v) => (v == null || v.toString().trim().isEmpty) ? null : v.toString();

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String? _first(List<String?> values) {
  for (final v in values) {
    if (v != null && v.trim().isNotEmpty) return v;
  }
  return null;
}
