import '../../../core/widgets/progress_bar.dart';

/// Where a budget stands against the time gone in its period.
class BudgetPace {
  const BudgetPace({required this.spentShare, required this.health, this.elapsedShare, this.projectedMinor});

  /// Spent / limit (can exceed 1).
  final double spentShare;

  /// Share of the period already gone (0..1), or null when the period is unknown.
  final double? elapsedShare;

  /// Spend at the end of the period if it continues at the current pace; null
  /// when it is too early in the period to say, or the period is unknown.
  final int? projectedMinor;
  final BudgetHealth health;

  /// Spending faster than time is passing.
  bool get overPace => elapsedShare != null && spentShare > elapsedShare!;
}

DateTime? _date(String? ymd) {
  if (ymd == null || ymd.isEmpty) return null;
  final d = DateTime.tryParse(ymd);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Below this share of the period a projection is too noisy (one purchase on
/// day 1 would "project" a huge overspend), so none is made.
const minElapsedForProjection = 0.2;

/// Computes pace and a projection from what the budgets endpoint returns.
/// [from]/[to] are the period bounds as `YYYY-MM-DD` (inclusive).
BudgetPace budgetPace({
  required int spentMinor,
  required int limitMinor,
  String? from,
  String? to,
  double alertThreshold = 0.8,
  DateTime? now,
}) {
  final spentShare = limitMinor > 0 ? spentMinor / limitMinor : (spentMinor > 0 ? double.infinity : 0.0);

  double? elapsed;
  final start = _date(from);
  final end = _date(to);
  if (start != null && end != null && !end.isBefore(start)) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final total = end.difference(start).inDays + 1;
    final gone = (day.difference(start).inDays + 1).clamp(0, total);
    elapsed = gone / total;
  }

  int? projected;
  if (elapsed != null && elapsed >= minElapsedForProjection) {
    projected = (spentMinor / elapsed).round();
  }

  final BudgetHealth health;
  if (limitMinor > 0 ? spentMinor > limitMinor : spentMinor > 0) {
    health = BudgetHealth.over;
  } else if ((projected != null && projected > limitMinor) || (alertThreshold > 0 && spentShare >= alertThreshold)) {
    health = BudgetHealth.atRisk;
  } else {
    health = BudgetHealth.onTrack;
  }

  return BudgetPace(spentShare: spentShare, elapsedShare: elapsed, projectedMinor: projected, health: health);
}

/// The last complete period before [now]: the previous calendar month for a
/// monthly budget, the previous Monday–Sunday week for a weekly one. Returns
/// `(from, to)` as `YYYY-MM-DD`.
(String, String) lastFullPeriod(String period, {DateTime? now}) {
  final today = now ?? DateTime.now();
  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (period == 'weekly') {
    final thisMonday = DateTime(today.year, today.month, today.day).subtract(Duration(days: today.weekday - 1));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    return (ymd(lastMonday), ymd(thisMonday.subtract(const Duration(days: 1))));
  }
  final firstThisMonth = DateTime(today.year, today.month, 1);
  final lastMonthEnd = firstThisMonth.subtract(const Duration(days: 1));
  return (ymd(DateTime(lastMonthEnd.year, lastMonthEnd.month, 1)), ymd(lastMonthEnd));
}
