import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/widgets/app_date_field.dart';
import 'package:mulinda_mobile/features/plan/widgets/plan_form_kit.dart';

void main() {
  test('the initial date is kept inside the allowed range', () {
    final first = DateTime(2026, 11, 7);
    final last = DateTime(2030, 1, 1);
    expect(clampDate(DateTime(2026, 11, 6, 15), first, last), DateTime(2026, 11, 7));
    expect(clampDate(DateTime(2031, 5, 1), first, last), DateTime(2030, 1, 1));
    expect(clampDate(DateTime(2027, 3, 4, 9), first, last), DateTime(2027, 3, 4));
  });

  testWidgets('a goal target date (first date tomorrow, no value) opens the picker', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => pkDate(
              context: context,
              label: 'Target date',
              value: null,
              firstDate: DateTime.now().add(const Duration(days: 1)),
              onPick: (d) => picked = d,
            ),
          ),
        ),
      ),
    );
    expect(find.text('common.chooseDate'), findsOneWidget);

    await tester.tap(find.byType(AppDateField));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('a clearable field clears to null', (tester) async {
    DateTime? value = DateTime(2026, 1, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) =>
                AppDateField(label: 'From', value: value, clearable: true, onChanged: (d) => setState(() => value = d)),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(value, isNull);
    expect(find.text('common.chooseDate'), findsOneWidget);
  });
}
