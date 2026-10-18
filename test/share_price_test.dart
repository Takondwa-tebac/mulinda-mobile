import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/plan/data/plan_models.dart';
import 'package:mulinda_mobile/features/plan/widgets/mse_logo.dart';

Map<String, dynamic> _money(int minor) => {
      'minor_units': minor,
      'currency': 'MWK',
      'amount': minor / 100,
      'formatted': 'MK ${minor / 100}',
    };

void main() {
  group('the last trade of a share', () {
    test('reads the price, the move and the gain on the units held', () {
      final item = InvestmentItem.fromJson({
        'id': 'i1',
        'name': 'NBM',
        'type': 'shares',
        'details': {'ticker': 'NBM', 'units': 1000},
        'last_trade': {
          'priced_on': '2026-10-09',
          'price': _money(5700),
          'change': _money(-300),
          'change_percent': -0.05,
          'day_gain': _money(-300000),
        },
      });

      final t = item.lastTrade!;
      expect(item.ticker, 'NBM');
      expect(t.isDown, true);
      expect(t.isUp, false);
      expect(t.changePercent, -0.05);
      expect(t.dayGain!.minorUnits, -300000);
    });

    test('with only one price there is no move yet', () {
      final t = ShareTrade.fromJson({'priced_on': '2026-10-09', 'price': _money(5700)});

      expect(t.hasChange, false);
      expect(t.dayGain, isNull);
    });

    test('a holding without prices has no last trade', () {
      expect(InvestmentItem.fromJson({'id': 'i2'}).lastTrade, isNull);
    });
  });

  group('company logos', () {
    test('every listed company has a bundled logo file', () {
      for (final ticker in ['AIRTEL', 'BHL', 'CHL', 'FDHB', 'FMBCH', 'ICON', 'ILLOVO', 'MPICO', 'NBM', 'NBS', 'NICO', 'NITL', 'OMU', 'PCL', 'STANDARD', 'SUNBIRD', 'TNM']) {
        final asset = mseLogoAsset(ticker);
        expect(asset, isNotNull, reason: ticker);
        expect(File(asset!).existsSync(), true, reason: '$ticker -> $asset');
      }
    });

    test('tickers are matched ignoring capitals and spaces; unknown ones have no logo', () {
      expect(mseLogoAsset(' nbm '), 'assets/mse_logos/nbm.png');
      expect(mseLogoAsset('XYZ'), isNull);
      expect(mseLogoAsset(null), isNull);
    });

    testWidgets('a company without a logo shows its initials', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MseLogo(ticker: 'XYZ', name: 'Some Company'))));

      expect(find.text('SC'), findsOneWidget);
    });
  });
}
