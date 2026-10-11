import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/insights/screens/notification_detail_screen.dart';
import 'package:mulinda_mobile/features/plan/data/investment_types.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';

void main() {
  test('a type says which reminders it can have', () {
    final vsla = InvestmentTypeDef.fromJson({
      'type': 'vsla',
      'label': {'en': 'Village savings group'},
      'reminders': ['meeting'],
      'fields': <dynamic>[],
    });
    final deposit = InvestmentTypeDef.fromJson({'type': 'fixed_deposit', 'label': {'en': 'Fixed deposit'}, 'fields': <dynamic>[]});

    expect(vsla.reminders, ['meeting']);
    expect(deposit.reminders, isEmpty);
  });

  test('reminders are on for a holding unless the server says otherwise', () {
    expect(InvestmentItem.fromJson({'id': 'a'}).remindersEnabled, true);
    expect(InvestmentItem.fromJson({'id': 'a', 'reminders_enabled': true}).remindersEnabled, true);
    expect(InvestmentItem.fromJson({'id': 'a', 'reminders_enabled': false}).remindersEnabled, false);
  });

  test('the investment reminders have their own notification icons', () {
    expect(iconForInsightType('investment_contribution_due'), Icons.event_repeat_outlined);
    expect(iconForInsightType('investment_meeting'), Icons.groups_outlined);
    expect(iconForInsightType('investment_payout'), Icons.payments_outlined);
  });
}
