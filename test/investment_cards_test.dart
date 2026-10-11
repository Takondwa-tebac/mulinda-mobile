import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/plan/data/investment_types.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/plan/data/plan_repository.dart';
import 'package:mulinda_mobile/features/plan/screens/plan_lists.dart';

Map<String, dynamic> _money(int minor) => {
      'minor_units': minor,
      'currency': 'MWK',
      'amount': minor / 100,
      'formatted': 'MK ${(minor / 100).toStringAsFixed(2)}',
    };

void main() {
  group('a savings circle', () {
    final rosca = InvestmentTypeDef.fromJson({
      'type': 'rosca',
      'label': {'en': 'Chipereganyu'},
      'valuation': 'periodic',
      'contributions': true,
      'estimate': {
        'label': {'en': 'Estimated payout'},
        'multiply': ['contribution_amount', 'members'],
        'override_field': 'payout_amount',
      },
      'derivation': {'contribution_field': 'contribution_amount', 'count_field': 'contributions_made'},
      'fields': <dynamic>[],
    });

    test('estimates the payout as the contribution times the members', () {
      expect(rosca.contributions, true);
      expect(rosca.estimatePayout({'contribution_amount': 10000, 'members': 10}), 100000);
    });

    test('a payout the user typed replaces the estimate', () {
      expect(rosca.estimatePayout({'contribution_amount': 10000, 'members': 10, 'payout_amount': 95000}), 95000);
    });

    test('has no estimate until the numbers are there', () {
      expect(rosca.estimatePayout({'contribution_amount': 10000}), isNull);
      expect(rosca.estimatePayout({}), isNull);
    });

    test('a holding keeps its forecast, contributions and next due date', () {
      final item = InvestmentItem.fromJson({
        'id': 'i1',
        'name': 'Chipereganyu',
        'type': 'rosca',
        'forecast': {
          'expected_payout': _money(10000000),
          'payout_is_estimate': true,
          'payout_date': '2026-11-01',
          'cycle_total': _money(10000000),
          'rounds_remaining': 6,
        },
        'contributions': {'count': 2, 'total': _money(2000000)},
        'next_due': {'date': '2026-10-15', 'overdue': true},
      });

      expect(item.forecast!.isEstimate, true);
      expect(item.forecast!.roundsRemaining, 6);
      expect(item.forecast!.payoutDate, '2026-11-01');
      expect(item.contributions!.count, 2);
      expect(item.nextDue!.overdue, true);
      expect(InvestmentItem.fromJson({'id': 'i2'}).forecast, isNull);
    });
  });

  group('investment cards', () {
    InvestmentItem item(String name) => InvestmentItem.fromJson({
          'id': 'i1',
          'name': name,
          'type': 'rosca',
          'status': 'active',
          'amount_invested': _money(2500000000),
          'current_value': _money(2500000000),
          'gain': _money(-123456789),
        });

    for (final width in [320.0, 360.0, 412.0]) {
      testWidgets('a very long name and large amounts do not overflow at ${width.toInt()} px wide', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(ProviderScope(
          overrides: [
            investmentsListProvider.overrideWith((ref) async => [
                  item('Chipereganyu of the Tuesday market women savings and loan circle in Area 25'),
                ]),
          ],
          child: const MaterialApp(home: InvestmentsListScreen()),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Chipereganyu of the Tuesday'), findsOneWidget);
      });
    }
  });
}
