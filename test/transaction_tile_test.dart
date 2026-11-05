import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/core/theme/semantic_colors.dart';
import 'package:mulinda_mobile/core/widgets/amount_text.dart';
import 'package:mulinda_mobile/core/widgets/empty_state.dart';
import 'package:mulinda_mobile/core/widgets/transaction_tile.dart';

const _amount = Money(minorUnits: 250000, currency: 'MWK', amount: 2500, formatted: 'MK 2,500.00');

TransactionTileData _data({
  String type = 'expense',
  bool needs = false,
  String? category = 'Food',
  bool pending = false,
}) => TransactionTileData(
  id: 't1',
  title: 'Shoprite',
  amount: _amount,
  type: type,
  categoryName: category,
  categoryIcon: 'restaurant',
  categoryColor: '#E67E22',
  meta: '14:05',
  needsAttention: needs,
  pending: pending,
);

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

Text _amountText(WidgetTester tester) =>
    tester.widget<Text>(find.descendant(of: find.byType(AmountText), matching: find.byType(Text)));

void main() {
  group('TransactionTile', () {
    testWidgets('shows merchant, "category · time" and a signed amount', (tester) async {
      await tester.pumpWidget(_wrap(TransactionTile(data: _data())));

      expect(find.text('Shoprite'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text(' · 14:05'), findsOneWidget);
      expect(find.text('-MK 2,500.00'), findsOneWidget);
    });

    testWidgets('hides the confirm-category chip when the category is settled', (tester) async {
      await tester.pumpWidget(_wrap(TransactionTile(data: _data())));
      expect(find.byKey(const ValueKey('confirm-category-chip')), findsNothing);
    });

    testWidgets('shows the confirm-category chip when it needs attention, and it is tappable', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(TransactionTile(data: _data(needs: true), onConfirmCategory: () => tapped++)));

      expect(find.byKey(const ValueKey('confirm-category-chip')), findsOneWidget);
      expect(find.text('activity2.confirmCategory'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-category-chip')));
      expect(tapped, 1);
    });

    testWidgets('an uncategorised row asks to add a category instead', (tester) async {
      await tester.pumpWidget(_wrap(TransactionTile(data: _data(needs: true, category: null))));
      expect(find.text('activity2.addCategory'), findsOneWidget);
    });

    testWidgets('income is "+" in the income colour, expense "-" in the expense colour', (tester) async {
      final s = SemanticColors.light;

      await tester.pumpWidget(_wrap(TransactionTile(data: _data(type: 'income'))));
      expect(_amountText(tester).data, '+MK 2,500.00');
      expect(_amountText(tester).style?.color, s.income);

      await tester.pumpWidget(_wrap(TransactionTile(data: _data(type: 'expense'))));
      expect(_amountText(tester).data, '-MK 2,500.00');
      expect(_amountText(tester).style?.color, s.expense);
      expect(s.income, isNot(s.expense));
    });

    testWidgets('a non-spending expense is neutral and labelled, not expense-coloured', (tester) async {
      const data = TransactionTileData(
        id: 't2',
        title: 'To my savings',
        amount: _amount,
        type: 'expense',
        categoryName: 'Moving my money',
        categoryIcon: 'swap_horiz',
        notSpending: true,
      );
      await tester.pumpWidget(_wrap(const TransactionTile(data: data)));

      expect(find.byKey(const ValueKey('not-spending-label')), findsOneWidget);
      expect(find.text('activity2.notSpending'), findsOneWidget);
      expect(_amountText(tester).data, 'MK 2,500.00'); // no minus sign
      final color = _amountText(tester).style?.color;
      expect(color, isNot(SemanticColors.light.expense));
      expect(color, AppTheme.light.colorScheme.onSurfaceVariant);
      expect(find.byIcon(Icons.swap_horiz), findsWidgets);
    });

    testWidgets('an ordinary expense has no "not counted" label', (tester) async {
      await tester.pumpWidget(_wrap(TransactionTile(data: _data())));
      expect(find.byKey(const ValueKey('not-spending-label')), findsNothing);
    });

    testWidgets('marks rows that are waiting to sync', (tester) async {
      await tester.pumpWidget(_wrap(TransactionTile(data: _data(pending: true))));
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    });
  });

  group('AmountText.label', () {
    test('never doubles a minus sign', () {
      const negative = Money(minorUnits: -100, currency: 'MWK', amount: -1, formatted: '-MK 1.00');
      expect(AmountText.label(negative, MoneyDirection.expense), '-MK 1.00');
      expect(AmountText.label(_amount, MoneyDirection.neutral), 'MK 2,500.00');
    });
  });

  group('EmptyState', () {
    testWidgets('shows title, body and calls the action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing yet',
            body: 'Add your first one.',
            actionLabel: 'Add',
            onAction: () => tapped = true,
          ),
        ),
      );

      expect(find.text('Nothing yet'), findsOneWidget);
      expect(find.text('Add your first one.'), findsOneWidget);
      await tester.tap(find.text('Add'));
      expect(tapped, isTrue);
    });

    testWidgets('has no button without an action', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(icon: Icons.inbox_outlined, title: 'Nothing yet')));
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
