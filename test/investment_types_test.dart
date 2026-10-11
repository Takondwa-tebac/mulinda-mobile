import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/plan/data/investment_types.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';

void main() {
  final shares = InvestmentTypeDef.fromJson({
    'type': 'shares',
    'label': {'en': 'Shares', 'ny': 'Magawo (Shares)'},
    'description': {'en': 'Shares in a company.'},
    'valuation': 'units_x_price',
    'requires_maturity': false,
    'interest': false,
    'derives_amount_invested': true,
    'derives_value': true,
    'derivation': <String, dynamic>{},
    'fields': [
      {'key': 'company', 'kind': 'text', 'required': true, 'label': {'en': 'Company', 'ny': 'Dzina la kampani'}},
      {
        'key': 'exchange',
        'kind': 'select',
        'required': false,
        'label': {'en': 'Where it is traded'},
        'options': [
          {'value': 'mse', 'label': {'en': 'Malawi Stock Exchange'}},
        ],
      },
      {'key': 'units', 'kind': 'number', 'required': true, 'label': {'en': 'Number of shares'}},
    ],
  });

  test('a type is read from the server with its fields and options in both languages', () {
    expect(shares.label('ny'), 'Magawo (Shares)');
    expect(shares.label('xx'), 'Shares'); // falls back to English
    expect(shares.fields.first.label('ny'), 'Dzina la kampani');
    expect(shares.fields[1].options.single.label('en'), 'Malawi Stock Exchange');
    expect(shares.fields[2].isNumeric, true);
    expect(shares.derivesAmountInvested, true);
  });

  test('shares: invested is units x price plus fees, value is units x today\'s price', () {
    final r = shares.derive({'units': 1000, 'buy_price': 50, 'fees': 500, 'current_price': 65});
    expect(r.invested, 50500);
    expect(r.value, 65000);
  });

  test('shares without a price today have no value of their own yet', () {
    final r = shares.derive({'units': 10, 'buy_price': 100});
    expect(r.invested, 1000);
    expect(r.value, isNull);
  });

  test('nothing is worked out until the needed numbers are typed', () {
    expect(shares.derive({'units': 10}).invested, isNull);
  });

  test('a savings circle: invested is the contribution times the rounds paid', () {
    final rosca = InvestmentTypeDef.fromJson({
      'type': 'rosca',
      'label': {'en': 'Savings circle'},
      'valuation': 'periodic',
      'derives_amount_invested': true,
      'derives_value': true,
      'derivation': {'contribution_field': 'contribution_amount', 'count_field': 'contributions_made'},
      'fields': <dynamic>[],
    });

    final r = rosca.derive({'contribution_amount': 20000, 'contributions_made': 4});
    expect(r.invested, 80000);
    expect(r.value, 80000);
  });

  test('a savings policy is worth its surrender value when given', () {
    final policy = InvestmentTypeDef.fromJson({
      'type': 'savings_policy',
      'label': {'en': 'Savings policy'},
      'valuation': 'periodic',
      'derives_amount_invested': true,
      'derives_value': true,
      'derivation': {'contribution_field': 'premium_amount', 'count_field': 'premiums_paid', 'value_field': 'surrender_value'},
      'fields': <dynamic>[],
    });

    final r = policy.derive({'premium_amount': 15000, 'premiums_paid': 12, 'surrender_value': 150000});
    expect(r.invested, 180000);
    expect(r.value, 150000);
  });

  test('a SACCO is worth its share capital plus savings', () {
    final sacco = InvestmentTypeDef.fromJson({
      'type': 'sacco',
      'label': {'en': 'SACCO'},
      'valuation': 'recorded',
      'derives_value': true,
      'derivation': {
        'value_fields': ['share_capital', 'savings_balance'],
      },
      'fields': <dynamic>[],
    });

    expect(sacco.derive({'share_capital': 40000, 'savings_balance': 70000}).value, 110000);
    expect(sacco.derive({}).value, isNull);
  });

  test('without the server\'s list the plain kinds are still available', () {
    expect(fallbackInvestmentTypes.map((t) => t.type), containsAll(['fixed_deposit', 'shares', 'other']));
    expect(fallbackInvestmentTypes.firstWhere((t) => t.type == 'fixed_deposit').requiresMaturity, true);
  });

  test('an investment keeps its details', () {
    final item = InvestmentItem.fromJson({
      'id': 'i1',
      'name': 'NBM shares',
      'type': 'shares',
      'details': {'company': 'NBM', 'units': 1000},
    });
    expect(item.details['company'], 'NBM');
    expect(InvestmentItem.fromJson({'id': 'i2'}).details, isEmpty);
  });
}
