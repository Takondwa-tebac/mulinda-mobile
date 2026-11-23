import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/money/money.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/core/widgets/amount_text.dart';
import 'package:mulinda_mobile/features/analytics/widgets/home_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FileLoader extends AssetLoader {
  const _FileLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

const _negative = Money(
  minorUnits: -37123924,
  currency: 'MWK',
  amount: -371239.24,
  formatted: 'MK -371,239.24',
  formattedWhole: 'MK -371,239',
);

Future<void> _pump(WidgetTester tester, Widget child, {bool dark = false}) async {
  tester.view.physicalSize = const Size(320 * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ny')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _FileLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();
}

/// The no-break space AmountText puts between the currency and the number.
final _nb = String.fromCharCode(0x00A0);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  test('AmountText never breaks between the currency and the number', () {
    expect(AmountText.unbreakable('MK -371,239.24'), 'MK${_nb}-371,239.24');
    expect(AmountText.unbreakable('MK -371,239.24').contains(' '), isFalse);
  });

  testWidgets('AmountText is a single unbreakable line', (tester) async {
    await _pump(tester, const AmountText(_negative, signed: false));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.softWrap, isFalse);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  for (final dark in [false, true]) {
    testWidgets('Money in your accounts shows a large negative balance in full at 320 px, 1.3x (${dark ? 'dark' : 'light'})',
        (tester) async {
      await _pump(tester, MoneyInAccountsRow(amount: _negative, accounts: 4, onTap: () {}), dark: dark);
      expect(tester.takeException(), isNull);
      // The whole kwacha figure, number included, not just "MK".
      final finder = find.text('MK${_nb}-371,239');
      expect(finder, findsOneWidget);
      final rendered = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(AmountText), matching: find.byType(RichText)),
      );
      expect(rendered.didExceedMaxLines, isFalse);
      // The amount fits inside the row.
      final row = tester.getRect(find.byKey(const ValueKey('home-money-in-accounts')));
      final amount = tester.getRect(finder);
      expect(amount.right, lessThanOrEqualTo(row.right));
      expect(amount.width, greaterThan(0));
    });
  }
}
