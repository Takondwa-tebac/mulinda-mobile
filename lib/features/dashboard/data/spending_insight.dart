import 'dashboard_models.dart';

/// A change in one category's spending vs the same days of last month.
class SpendingInsight {
  const SpendingInsight({required this.categoryName, required this.percent, required this.up});

  final String categoryName;

  /// Whole percent, always positive; see [up] for the direction.
  final int percent;
  final bool up;
}

/// Smallest change worth mentioning.
const _minChange = 0.10;

/// The most notable category change, computed only from the numbers the
/// server returned. Returns null (say nothing) when there is no comparable
/// previous amount, the change is small, or the data is missing — it never
/// guesses.
SpendingInsight? spendingInsight(List<CategorySpend> rows) {
  CategorySpend? best;
  var bestDelta = 0;
  for (final r in rows) {
    // "Other" lumps categories together; a change there means nothing specific.
    if (r.categoryId == null || r.name.trim().isEmpty) continue;
    final prev = r.previousAmount.minorUnits;
    final now = r.amount.minorUnits;
    if (prev <= 0 || now < 0) continue;
    if (r.amount.currency != r.previousAmount.currency) continue;
    final change = (now - prev) / prev;
    if (change.abs() < _minChange) continue;
    final delta = (now - prev).abs();
    if (delta > bestDelta) {
      best = r;
      bestDelta = delta;
    }
  }
  if (best == null) return null;
  final prev = best.previousAmount.minorUnits;
  final change = (best.amount.minorUnits - prev) / prev;
  return SpendingInsight(categoryName: best.name, percent: (change.abs() * 100).round(), up: change > 0);
}

/// Share of this month's spending that sits in rows without a category
/// ("Other" / uncategorised, i.e. no `category_id`). 0 when there is nothing.
double uncategorisedShare(List<CategorySpend> rows) {
  var total = 0;
  var none = 0;
  for (final r in rows) {
    if (r.amount.minorUnits <= 0) continue;
    total += r.amount.minorUnits;
    if (r.categoryId == null) none += r.amount.minorUnits;
  }
  return total == 0 ? 0 : none / total;
}
