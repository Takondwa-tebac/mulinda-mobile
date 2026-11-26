import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/analytics/data/analytics_models.dart';
import 'package:mulinda_mobile/features/analytics/widgets/report_period.dart';

void main() {
  testWidgets('"Pick dates" is reachable and opens the range picker on a short screen', (tester) async {
    // Short screen: before the fix the last row sat below the bottom edge.
    tester.view.physicalSize = const Size(430, 600) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    showPeriodSheet(ctx, PeriodSelection.defaultPeriod);
    await tester.pumpAndSettle();

    final pick = find.byKey(const ValueKey('period-option-pick'));
    await tester.ensureVisible(pick);
    await tester.pumpAndSettle();
    await tester.tap(pick);
    await tester.pumpAndSettle();

    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  });
}
