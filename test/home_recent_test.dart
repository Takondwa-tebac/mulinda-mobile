import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/dashboard/data/dashboard_models.dart';

final _amount = {'minor_units': 100000, 'currency': 'MWK', 'amount': 1000, 'formatted': 'MK 1,000.00'};

void main() {
  test('recent rows read category_detail and categorisation (round-2 API)', () {
    final t = RecentTxn.fromJson({
      'id': 'r1',
      'date': '2026-11-05',
      'type': 'expense',
      'amount': _amount,
      'merchant': 'Shoprite',
      'category': 'Food',
      'category_detail': {'id': 'c1', 'name': 'Food', 'icon': 'restaurant', 'color': '#E67E22', 'is_spending': true},
      'categorisation': {'status': 'suggested', 'source': 'keyword', 'confidence': 0.8, 'needs_attention': true},
    });
    expect(t.category, 'Food');
    expect(t.categoryIcon, 'restaurant');
    expect(t.categoryColor, '#E67E22');
    expect(t.needsAttention, isTrue);
    expect(t.categorisationStatus, 'suggested');
    expect(t.notSpending, isFalse);
  });

  test('older servers (category as a plain name, no categorisation) still work', () {
    final t = RecentTxn.fromJson({
      'id': 'r2',
      'date': '2026-11-05',
      'type': 'expense',
      'amount': _amount,
      'category': 'Rent',
    });
    expect(t.category, 'Rent');
    expect(t.categoryIcon, isNull);
    expect(t.needsAttention, isFalse);
  });

  test('a non-spending category and transfers never ask for a category', () {
    final moved = RecentTxn.fromJson({
      'id': 'r3',
      'date': '2026-11-05',
      'type': 'expense',
      'amount': _amount,
      'category_detail': {'id': 'own', 'name': 'Moving my money', 'icon': 'swap_horiz', 'is_spending': false},
    });
    expect(moved.notSpending, isTrue);

    final transfer = RecentTxn.fromJson({
      'id': 'r4',
      'date': '2026-11-05',
      'type': 'transfer',
      'amount': _amount,
      'categorisation': {'status': 'uncategorised', 'needs_attention': true},
    });
    expect(transfer.needsAttention, isFalse);
  });
}
