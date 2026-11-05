import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/activity/data/day_grouping.dart';
import 'package:mulinda_mobile/features/transactions/screens/transaction_detail_screen.dart';

Map<String, dynamic> _money(int minor) => {
  'minor_units': minor,
  'currency': 'MWK',
  'amount': minor / 100,
  'formatted': 'MK ${minor ~/ 100}',
};

Txn _txn(String id, String type, int minor, String? at) =>
    Txn.fromJson({'id': id, 'type': type, 'amount': _money(minor), 'occurred_at': at});

void main() {
  group('grouping by day', () {
    // Local-time timestamps (no zone), so the test does not depend on the machine's zone.
    final txns = [
      _txn('a', 'expense', 1000, '2026-11-04T18:00:00'),
      _txn('b', 'income', 5000, '2026-11-04T09:00:00'),
      _txn('c', 'transfer', 7000, '2026-11-04T08:00:00'),
      _txn('d', 'expense', 300, '2026-11-03T23:59:00'),
      _txn('e', 'expense', 200, null),
      _txn('f', 'expense', 100, '2026-11-01T10:00:00'),
    ];

    test('keeps the newest-first order and puts undated rows last', () {
      final groups = groupByDay(txns);
      expect(groups.map((g) => g.day), [DateTime(2026, 11, 4), DateTime(2026, 11, 3), DateTime(2026, 11, 1), null]);
      expect(groups.first.items.map((t) => t.id), ['a', 'b', 'c']);
    });

    test('totals money in and out per day, leaving transfers out', () {
      final today = groupByDay(txns).first;
      expect(today.inMinor, 5000);
      expect(today.outMinor, 1000);
      expect(today.netMinor, 4000);
      expect(today.currency, 'MWK');
    });

    test('does not add up a day that mixes currencies', () {
      final usd = Txn.fromJson({
        'id': 'u',
        'type': 'expense',
        'amount': {'minor_units': 100, 'currency': 'USD', 'amount': 1, 'formatted': '\$ 1.00'},
        'occurred_at': '2026-11-04T10:00:00',
      });
      final g = groupByDay([txns.first, usd]).single;
      expect(g.currency, isNull);
      expect(g.outMinor, 0);
    });

    test('labels today, yesterday and other days', () {
      final now = DateTime(2026, 11, 4, 8);
      expect(dayKind(DateTime(2026, 11, 4), now), DayKind.today);
      expect(dayKind(DateTime(2026, 11, 3), now), DayKind.yesterday);
      expect(dayKind(DateTime(2026, 10, 31), now), DayKind.other);
      expect(dayKind(null, now), DayKind.unknown);
    });
  });

  group('categorisation block', () {
    test('is read when present', () {
      final t = Txn.fromJson({
        'id': '1',
        'type': 'expense',
        'amount': _money(100),
        'category': {'id': 'c1', 'name': 'Transport', 'icon': 'directions_bus', 'color': '#3498DB'},
        'categorisation': {'status': 'suggested', 'source': 'keyword', 'confidence': 0.82, 'needs_attention': true},
      });
      expect(t.categorisation?.status, 'suggested');
      expect(t.categorisation?.source, 'keyword');
      expect(t.categorisation?.confidence, closeTo(0.82, 1e-9));
      expect(t.needsCategory, isTrue);
      expect(t.hasSuggestedCategory, isTrue);
      expect(t.categoryIcon, 'directions_bus');
      expect(t.categoryColor, '#3498DB');
    });

    test('is optional (older API) and then nothing needs attention', () {
      final t = Txn.fromJson({'id': '1', 'type': 'expense', 'amount': _money(100)});
      expect(t.categorisation, isNull);
      expect(t.needsCategory, isFalse);
    });

    test('a confirmed copy no longer needs attention', () {
      final t = Txn.fromJson({
        'id': '1',
        'type': 'expense',
        'amount': _money(100),
        'categorisation': {'status': 'uncategorised', 'needs_attention': true},
      });
      final fixed = t.withCategory(const Category(id: 'c2', name: 'Food', kind: 'expense'));
      expect(fixed.categoryId, 'c2');
      expect(fixed.categorisation?.isConfirmed, isTrue);
      expect(fixed.needsCategory, isFalse);
    });
  });

  group('non-spending categories', () {
    Txn moved() => Txn.fromJson({
      'id': 'm',
      'type': 'expense',
      'amount': _money(9000),
      'occurred_at': '2026-11-04T12:00:00',
      'category': {'id': 'own', 'name': 'Moving my money', 'icon': 'swap_horiz', 'is_spending': false},
    });

    test('is_spending is read and defaults to true', () {
      expect(moved().notSpending, isTrue);
      expect(moved().countsAsSpending, isFalse);
      expect(Category.fromJson({'id': '1', 'name': 'Food'}).isSpending, isTrue);
      expect(Category.fromJson({'id': '2', 'name': 'Own', 'is_spending': false}).isSpending, isFalse);
    });

    test('is left out of the money out for the day', () {
      final g = groupByDay([moved(), _txn('x', 'expense', 1000, '2026-11-04T10:00:00')]).single;
      expect(g.outMinor, 1000);
    });
  });

  group('list filters and pages', () {
    test('send only what is set, in the contract names', () {
      final q = TxnQuery(
        search: '  shoprite ',
        type: 'expense',
        categoryId: 'c1',
        accountId: 'a1',
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 4),
        needsCategory: true,
      );
      expect(q.toParams(), {
        'search': 'shoprite',
        'type': 'expense',
        'category_id': 'c1',
        'financial_account_id': 'a1',
        'from': '2026-11-01',
        'to': '2026-11-04T23:59:59',
        'needs_category': 1,
      });
      expect(TxnQuery.none.toParams(), isEmpty);
      expect(TxnQuery.none.isDefault, isTrue);
      expect(const TxnQuery(needsCategory: true).isDefault, isFalse);
    });

    test('more pages come from meta, else from a full page', () {
      final withMeta = parseTxnPage(
        {
          'data': [],
          'meta': {'current_page': 1, 'last_page': 3, 'total': 120},
        },
        page: 1,
        perPage: 50,
      );
      expect(withMeta.hasMore, isTrue);
      expect(withMeta.total, 120);

      final last = parseTxnPage(
        {
          'data': [],
          'meta': {'current_page': 3, 'last_page': 3},
        },
        page: 3,
        perPage: 50,
      );
      expect(last.hasMore, isFalse);

      final noMeta = parseTxnPage(
        {
          'data': List.generate(2, (i) => {'id': '$i', 'type': 'expense', 'amount': _money(1)}),
        },
        page: 1,
        perPage: 2,
      );
      expect(noMeta.hasMore, isTrue);
    });
  });

  group('detailAmountLabel', () {
    test('income is "+", spending "-", and money moved between own accounts is unsigned', () {
      final income = Txn.fromJson({'id': '1', 'type': 'income', 'amount': _money(5000)});
      final spend = Txn.fromJson({'id': '2', 'type': 'expense', 'amount': _money(5000)});
      final moved = Txn.fromJson({
        'id': '3',
        'type': 'expense',
        'amount': _money(5000),
        'category': {'id': 'c', 'name': 'Moving my money', 'kind': 'expense', 'is_spending': false},
      });

      expect(detailAmountLabel(income), '+MK 50');
      expect(detailAmountLabel(spend), '-MK 50');
      expect(moved.notSpending, isTrue);
      expect(detailAmountLabel(moved), 'MK 50');
    });
  });
}
