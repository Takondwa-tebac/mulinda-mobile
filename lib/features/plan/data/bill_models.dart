import '../../../core/money/money.dart';
import '../../activity/data/activity_models.dart';

/// A recurring bill (GET /recurring-patterns/{id}): what it is, roughly how
/// much, how often, when it is next due and the recent payments that matched.
class Bill {
  const Bill({
    required this.id,
    required this.label,
    required this.cadence,
    this.type,
    this.amount,
    this.nextDue,
    this.lastSeen,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.recent = const [],
  });

  final String id;
  final String label;

  /// weekly | monthly | … (the server's cadence value).
  final String cadence;
  final String? type;

  /// The average of recent payments, else the expected amount.
  final Money? amount;
  final DateTime? nextDue;
  final DateTime? lastSeen;
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColor;
  final List<Txn> recent;

  factory Bill.fromJson(Map<String, dynamic> j) {
    final category = j['category'] is Map ? (j['category'] as Map).cast<String, dynamic>() : null;
    DateTime? day(dynamic v) => DateTime.tryParse(v?.toString() ?? '');
    final money = j['average_amount'] is Map
        ? Money.parse(j['average_amount'])
        : (j['expected_amount'] is Map ? Money.parse(j['expected_amount']) : null);
    return Bill(
      id: j['id'].toString(),
      label: j['label']?.toString() ?? j['name']?.toString() ?? '',
      cadence: j['cadence']?.toString() ?? '',
      type: j['type']?.toString(),
      amount: money,
      nextDue: day(j['next_due_on'] ?? j['next_expected_at']),
      lastSeen: day(j['last_seen_at']),
      categoryName: category?['name']?.toString(),
      categoryIcon: category?['icon']?.toString(),
      categoryColor: category?['color']?.toString(),
      recent: ((j['recent_transactions'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Txn.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}
