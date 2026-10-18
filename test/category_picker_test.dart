import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/activity/data/activity_repository.dart';
import 'package:mulinda_mobile/features/activity/widgets/category_icons.dart';
import 'package:mulinda_mobile/features/activity/widgets/category_picker.dart';

const _food = Category(id: 'c1', name: 'Food', kind: 'expense', icon: 'restaurant', color: '#E67E22');
const _transport = Category(id: 'c2', name: 'Transport', kind: 'expense', icon: 'directions_bus', color: '#3498DB');
const _salary = Category(id: 'c3', name: 'Salary', kind: 'income', icon: 'payments');
const _all = [_food, _transport, _salary];

void main() {
  group('searching categories', () {
    test('matches part of the name, ignoring capitals, from the list on the phone', () {
      expect(filterCategories(_all, 'tra').map((c) => c.name), ['Transport']);
      expect(filterCategories(_all, '  FOO ').map((c) => c.name), ['Food']);
      expect(filterCategories(_all, ''), hasLength(3));
    });

    test('only offers categories of the kind being picked', () {
      expect(filterCategories(_all, '', kind: 'income').map((c) => c.name), ['Salary']);
    });

    test('offers to create what was typed only when no category has that name', () {
      expect(canCreateCategory(_all, 'Pets', kind: 'expense'), true);
      expect(canCreateCategory(_all, ' food ', kind: 'expense'), false);
      expect(canCreateCategory(_all, '', kind: 'expense'), false);
      // "Food" exists as an expense but not as income, so it can be created there.
      expect(canCreateCategory(_all, 'Food', kind: 'income'), true);
    });
  });

  group('category looks', () {
    test('icon names map to icons and unknown ones fall back to the generic tag', () {
      expect(categoryIcon('restaurant'), Icons.restaurant);
      expect(categoryIcon('something_new'), Icons.label_outline);
      expect(categoryIcon(null), Icons.label_outline);
    });

    test('colours are read from #RRGGBB and ignored when invalid', () {
      expect(parseHexColor('#E67E22'), const Color(0xFFE67E22));
      expect(parseHexColor('not a colour'), isNull);
      expect(parseHexColor(null), isNull);
    });

    test('a category keeps the icon and colour the server sends', () {
      final c = Category.fromJson({'id': '1', 'name': 'Food', 'kind': 'expense', 'icon': 'restaurant', 'color': '#E67E22'});
      expect(c.icon, 'restaurant');
      expect(c.color, '#E67E22');
      expect(Category.fromJson({'id': '2', 'name': 'X'}).icon, isNull);
    });
  });

  group('the picker', () {
    Future<void> open(WidgetTester tester, {String? selected}) async {
      String? chosen = selected;
      await tester.pumpWidget(ProviderScope(
        overrides: [categoriesProvider.overrideWith((ref) async => _all)],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CategoryPickerField(
                value: chosen,
                kind: 'expense',
                onChanged: (v) => setState(() => chosen = v),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CategoryPickerField));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the categories of the kind with their names', (tester) async {
      await open(tester);

      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Salary'), findsNothing); // an income category
    });

    testWidgets('typing narrows the list without leaving the sheet', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'tran');
      await tester.pumpAndSettle();

      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
    });

    testWidgets('says the category was not found and offers to create it', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Pets');
      await tester.pumpAndSettle();

      expect(find.text('categoryPicker.notFound'), findsOneWidget);
      expect(find.text('categoryPicker.createNamed'), findsOneWidget);
    });

    testWidgets('choosing a category fills the field', (tester) async {
      await open(tester);

      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byType(CategoryPickerField), matching: find.text('Transport')), findsOneWidget);
    });
  });
}
