/// One step of the product funnel (`steps[]` of GET /admin/analytics/funnel).
class FunnelStep {
  const FunnelStep({required this.name, required this.users, required this.events, this.conversion});

  final String name;
  final int users;
  final int events;

  /// Users ÷ the previous step's users (0..1); null for the first step or when
  /// the previous step had nobody.
  final double? conversion;

  factory FunnelStep.fromJson(Map<String, dynamic> j) => FunnelStep(
    name: j['name']?.toString() ?? '',
    users: (j['users'] as num?)?.toInt() ?? 0,
    events: (j['events'] as num?)?.toInt() ?? 0,
    conversion: (j['conversion'] as num?)?.toDouble(),
  );
}

/// The funnel for a date range: ordered steps, side events and trial → paid.
class FunnelReport {
  const FunnelReport({
    required this.steps,
    required this.secondary,
    required this.trialUsers,
    required this.paidUsers,
    this.trialToPaid,
    this.newUsersOnly = true,
  });

  final List<FunnelStep> steps;
  final List<FunnelStep> secondary;
  final int trialUsers;
  final int paidUsers;
  final double? trialToPaid;
  final bool newUsersOnly;

  /// Nothing happened in the range.
  bool get isEmpty => steps.every((s) => s.users == 0) && secondary.every((s) => s.users == 0);

  /// Users at the first step (the bars are drawn relative to it).
  int get top => steps.isEmpty ? 0 : steps.map((s) => s.users).reduce((a, b) => a > b ? a : b);

  factory FunnelReport.fromJson(Map<String, dynamic> j) {
    List<FunnelStep> list(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => FunnelStep.fromJson(e.cast<String, dynamic>())).toList()
        : const <FunnelStep>[];
    final conversion = j['conversion'] is Map ? (j['conversion'] as Map).cast<String, dynamic>() : const {};
    return FunnelReport(
      steps: list(j['steps']),
      secondary: list(j['secondary']),
      trialUsers: (conversion['trial_users'] as num?)?.toInt() ?? 0,
      paidUsers: (conversion['paid_users'] as num?)?.toInt() ?? 0,
      trialToPaid: (conversion['rate'] as num?)?.toDouble(),
      newUsersOnly: j['new_users_only'] != false,
    );
  }
}
