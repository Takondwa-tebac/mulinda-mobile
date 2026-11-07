import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/activity/widgets/category_quick_fix.dart';

const _food = Category(id: 'c-food', name: 'Food', kind: 'expense', icon: 'restaurant');
const _transport = Category(id: 'c-transport', name: 'Transport', kind: 'expense', icon: 'directions_bus');

/// Records what the sheet asks the server to do.
class _FakeRepo extends ActivityRepository {
  _FakeRepo({this.similar = 0}) : super(Dio());

  final int similar;
  final confirmed = <List<String>>[];
  final setCalls = <({String id, String? categoryId, bool applyToSimilar})>[];

  @override
  Future<void> confirmTransactions(List<String> ids) async => confirmed.add(ids);

  @override
  Future<CategoryUpdate> setCategory(String id, String? categoryId, {bool applyToSimilar = false}) async {
    setCalls.add((id: id, categoryId: categoryId, applyToSimilar: applyToSimilar));
    final cat = [_food, _transport].firstWhere((c) => c.id == categoryId);
    return CategoryUpdate(txn: _suggested.withCategory(cat), similarUpdated: similar);
  }
}

final _suggested = Txn.fromJson({
  'id': 't1',
  'type': 'expense',
  'merchant': 'Shoprite',
  'amount': {'minor_units': 250000, 'currency': 'MWK', 'amount': 2500, 'formatted': 'MK 2,500.00'},
  'category': {'id': 'c-food', 'name': 'Food', 'icon': 'restaurant'},
  'categorisation': {'status': 'suggested', 'source': 'keyword', 'confidence': 0.8, 'needs_attention': true},
});

Future<List<Txn>> _open(WidgetTester tester, _FakeRepo repo) async {
  final updates = <Txn>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activityRepositoryProvider.overrideWithValue(repo),
        categoriesProvider.overrideWith((ref) async => const [_food, _transport]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openCategoryQuickFix(context, ref, _suggested, onLocalUpdate: updates.add),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return updates;
}

void main() {
  testWidgets('shows the suggested category with a one-tap confirm', (tester) async {
    await _open(tester, _FakeRepo());
    expect(find.text('activity2.weThink'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-fix-confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-fix-similar')), findsOneWidget);
  });

  testWidgets('"Yes, correct" confirms the transaction', (tester) async {
    final repo = _FakeRepo();
    final updates = await _open(tester, repo);

    await tester.tap(find.byKey(const ValueKey('quick-fix-confirm')));
    await tester.pumpAndSettle();

    expect(repo.confirmed, [
      ['t1'],
    ]);
    expect(repo.setCalls, isEmpty);
    // Optimistic row: same category, now confirmed.
    expect(updates.last.categoryId, 'c-food');
    expect(updates.last.needsCategory, isFalse);
    expect(find.text('activity2.categoryConfirmed'), findsOneWidget);
  });

  testWidgets('"Yes, correct" with apply-to-similar uses the category endpoint', (tester) async {
    final repo = _FakeRepo(similar: 3);
    await _open(tester, repo);

    await tester.tap(find.byKey(const ValueKey('quick-fix-similar')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-fix-confirm')));
    await tester.pumpAndSettle();

    expect(repo.confirmed, isEmpty);
    expect(repo.setCalls.single, (id: 't1', categoryId: 'c-food', applyToSimilar: true));
    expect(find.text('activity2.updatedSimilar'), findsOneWidget);
  });

  testWidgets('picking another category saves it, with or without similar ones', (tester) async {
    final repo = _FakeRepo();
    final updates = await _open(tester, repo);

    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();

    expect(repo.setCalls.single, (id: 't1', categoryId: 'c-transport', applyToSimilar: false));
    expect(updates.first.categoryName, 'Transport'); // optimistic, before the server answered
    expect(find.text('activity2.categorySaved'), findsOneWidget);
  });

  testWidgets('apply-to-similar is passed through when picking a category', (tester) async {
    final repo = _FakeRepo(similar: 3);
    await _open(tester, repo);

    await tester.tap(find.byKey(const ValueKey('quick-fix-similar')));
    await tester.pump();
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();

    expect(repo.setCalls.single, (id: 't1', categoryId: 'c-transport', applyToSimilar: true));
  });
}
