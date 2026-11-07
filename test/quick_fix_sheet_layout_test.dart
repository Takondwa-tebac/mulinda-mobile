import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/activity/widgets/category_quick_fix.dart';
import 'package:mulinda_mobile/features/activity/widgets/txn_view.dart';

const _cats = [
  Category(id: 'c-food', name: 'Food', kind: 'expense', icon: 'restaurant'),
  Category(id: 'c-transport', name: 'Transport', kind: 'expense', icon: 'directions_bus'),
  Category(id: 'c-rent', name: 'Rent', kind: 'expense', icon: 'home'),
  Category(id: 'c-air', name: 'Airtime', kind: 'expense', icon: 'phone_android'),
  Category(id: 'c-fees', name: 'Bank charges', kind: 'expense'),
];

Txn _txn({String? merchant = 'Shoprite Area 47', String? counterparty, bool suggested = true}) => Txn.fromJson({
  'id': 't1',
  'type': 'expense',
  'merchant': merchant,
  'counterparty': counterparty,
  'amount': {'minor_units': 250000, 'currency': 'MWK', 'amount': 2500, 'formatted': 'MK 2,500.00'},
  if (suggested) 'category': {'id': 'c-food', 'name': 'Food'},
  'categorisation': {'status': suggested ? 'suggested' : 'uncategorised', 'needs_attention': true},
});

final _rootKey = GlobalKey<NavigatorState>();

/// Mimics the app shell: a tab's own Navigator inside a Scaffold that has a
/// floating button, and the sheet opened from inside the tab.
Future<void> _open(WidgetTester tester, Txn txn) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        categoriesProvider.overrideWith((ref) async => _cats),
        activityRepositoryProvider.overrideWithValue(ActivityRepository(Dio())),
      ],
      child: MaterialApp(
        navigatorKey: _rootKey,
        home: Scaffold(
          floatingActionButton: FloatingActionButton(key: const ValueKey('shell-fab'), onPressed: () {}),
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    onPressed: () => openCategoryQuickFix(context, ref, txn),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('reference-like merchants', () {
    test('bank references are recognised', () {
      expect(looksLikeReference('375870.1005120443.FT26278T9Q7Y.2.70'), isTrue);
      expect(looksLikeReference('FT26278T9Q7Y'), isTrue);
      expect(looksLikeReference('0991234567'), isTrue);
      expect(looksLikeReference('12.50'), isTrue);
    });

    test('ordinary names are not', () {
      expect(looksLikeReference('Shoprite Area 47'), isFalse);
      expect(looksLikeReference('Airtel Money'), isFalse);
      expect(looksLikeReference('LEFTOVERS FOODS'), isFalse);
      expect(looksLikeReference(null), isFalse);
      expect(looksLikeReference(''), isFalse);
    });

    test('a reference is replaced by the counterparty or a plain label', () {
      expect(displayMerchant(_txn(merchant: '375870.1005120443.FT26278T9Q7Y.2.70')), 'activity2.label.bankPayment');
      expect(
        displayMerchant(_txn(merchant: '375870.1005120443.FT26278T9Q7Y.2.70', counterparty: 'Kondwani Demo')),
        'Kondwani Demo',
      );
      expect(displayMerchant(_txn()), 'Shoprite Area 47');
      expect(cleanMerchant(_txn(merchant: 'FT26278T9Q7Y')), isNull);
    });
  });

  group('quick-fix sheet', () {
    testWidgets('opens above the tab navigator, so the shell button is not on top', (tester) async {
      await _open(tester, _txn());
      final sheetNavigator = tester.state<NavigatorState>(
        find.ancestor(of: find.byType(BottomSheet), matching: find.byType(Navigator)).first,
      );
      expect(sheetNavigator, _rootKey.currentState);
    });

    testWidgets('with the keyboard open the list stays visible and nothing overflows', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 760 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await _open(tester, _txn(merchant: 'A long shop name that goes on and on Area 47 Lilongwe'));

      // Keyboard up (~300 logical px) after focusing the search field.
      await tester.tap(find.byKey(const ValueKey('category-search')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The suggestion card and switch stepped aside; header and results remain.
      expect(find.byKey(const ValueKey('quick-fix-confirm')), findsNothing);
      expect(find.byKey(const ValueKey('quick-fix-merchant')).hitTestable(), findsOneWidget);
      expect(find.text('Transport').hitTestable(), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, 'air');
      await tester.pumpAndSettle();
      expect(find.text('Airtime').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bank-reference merchant gets a plain label and no "apply to all"', (tester) async {
      await _open(tester, _txn(merchant: '375870.1005120443.FT26278T9Q7Y.2.70'));
      expect(find.text('activity2.label.bankPayment'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-fix-similar')), findsNothing);
      expect(find.textContaining('FT26278T9Q7Y'), findsNothing);
    });

    testWidgets('a real merchant still offers "apply to all"', (tester) async {
      await _open(tester, _txn());
      expect(find.byKey(const ValueKey('quick-fix-similar')), findsOneWidget);
    });
  });
}
