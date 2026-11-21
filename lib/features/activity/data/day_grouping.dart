import 'activity_models.dart';

/// Transactions that happened on one calendar day (local time), with the day's
/// money in and out. Transfers and rows without a date are not counted.
class DayGroup {
  const DayGroup({
    required this.day,
    required this.items,
    required this.inMinor,
    required this.outMinor,
    this.currency,
  });

  /// Midnight of the day, local time; null for rows with no date.
  final DateTime? day;
  final List<Txn> items;
  final int inMinor;
  final int outMinor;

  /// The currency of the totals, or null when the day mixes currencies (then
  /// no total is shown rather than adding unlike amounts).
  final String? currency;

  int get netMinor => inMinor - outMinor;
}

/// How a day header reads.
enum DayKind { today, yesterday, other, unknown }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whether [day] is today, yesterday or another date, relative to [now].
DayKind dayKind(DateTime? day, DateTime now) {
  if (day == null) return DayKind.unknown;
  final diff = _dateOnly(now).difference(_dateOnly(day)).inDays;
  if (diff == 0) return DayKind.today;
  if (diff == 1) return DayKind.yesterday;
  return DayKind.other;
}

/// Groups [txns] by local calendar day, keeping the incoming order (the list
/// arrives newest first) and putting undated rows last.
List<DayGroup> groupByDay(List<Txn> txns) {
  final order = <DateTime?>[];
  final buckets = <DateTime?, List<Txn>>{};
  for (final t in txns) {
    final local = t.occurredLocal;
    final key = local == null ? null : _dateOnly(local);
    if (!buckets.containsKey(key)) {
      order.add(key);
      buckets[key] = [];
    }
    buckets[key]!.add(t);
  }
  // Undated rows go to the end.
  if (order.remove(null)) order.add(null);

  return [for (final key in order) _group(key, buckets[key]!)];
}

DayGroup _group(DateTime? day, List<Txn> items) {
  var inMinor = 0;
  var outMinor = 0;
  final currencies = <String>{};
  for (final t in items) {
    if (t.type == 'income') {
      inMinor += t.amount.minorUnits;
      currencies.add(t.amount.currency);
    } else if (t.countsAsSpending) {
      outMinor += t.amount.minorUnits;
      currencies.add(t.amount.currency);
    }
  }
  return DayGroup(
    day: day,
    items: items,
    inMinor: currencies.length <= 1 ? inMinor : 0,
    outMinor: currencies.length <= 1 ? outMinor : 0,
    currency: currencies.length == 1 ? currencies.first : null,
  );
}
