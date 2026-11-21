import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/theme/app_theme.dart';
import 'package:mulinda_mobile/core/widgets/country_picker.dart';
import 'package:mulinda_mobile/features/activity/data/activity_models.dart';
import 'package:mulinda_mobile/features/auth/data/auth_repository.dart';
import 'package:mulinda_mobile/features/auth/screens/register_screen.dart';
import 'package:mulinda_mobile/features/capture/data/sender_accounts.dart';
import 'package:mulinda_mobile/features/capture/data/sms_manual_scanner.dart';
import 'package:mulinda_mobile/features/dashboard/data/last_30_days.dart';
import 'package:mulinda_mobile/features/dashboard/widgets/first_visit_cards.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FileLoader extends AssetLoader {
  const _FileLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

/// Pumps [child] with the real English strings.
Future<void> _pumpLocalized(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
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
          builder: (context) => ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: child,
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

Map<String, dynamic> _m(int major) => {
  'minor_units': major * 100,
  'currency': 'MWK',
  'amount': major,
  'formatted': 'MK $major.00',
};

Account _account(String name, String type) => Account.fromJson({'id': name, 'name': name, 'type': type});

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  group('country picker search', () {
    String name(Country c) => const {
      'MW': 'Malawi',
      'ZM': 'Zambia',
      'MZ': 'Mozambique',
      'TZ': 'Tanzania',
      'ZW': 'Zimbabwe',
      'ZA': 'South Africa',
      'KE': 'Kenya',
      'UG': 'Uganda',
      'BW': 'Botswana',
      'GB': 'United Kingdom',
      'US': 'United States',
    }[c.iso]!;

    test('Malawi is first and the default', () {
      expect(kCountries.first, malawi);
      expect(malawi.dialLabel, '+265');
    });

    test('matches by any part of the name, any case', () {
      expect(filterCountries('mal', nameOf: name).map((c) => c.iso), ['MW']);
      expect(filterCountries('UNITED', nameOf: name).map((c) => c.iso), ['GB', 'US']);
      expect(filterCountries('  ', nameOf: name), kCountries);
    });

    test('matches by dialling code with or without the plus', () {
      expect(filterCountries('265', nameOf: name).map((c) => c.iso), ['MW']);
      expect(filterCountries('+260', nameOf: name).map((c) => c.iso), ['ZM']);
      expect(filterCountries('+44', nameOf: name).map((c) => c.iso), ['GB']);
    });

    test('nothing matches an unknown name', () {
      expect(filterCountries('narnia', nameOf: name), isEmpty);
    });

    test('builds the international number without the trunk zero', () {
      expect(internationalNumber(malawi, '0991 23 45 67'), '+265991234567');
      expect(internationalNumber(const Country('ZM', '260'), '977-123456'), '+260977123456');
    });

    testWidgets('the sheet filters as you type and returns the pick', (tester) async {
      Country? picked;
      await _pumpLocalized(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: CountryCodeButton(country: malawi, onChanged: (c) => picked = c),
          ),
        ),
      );
      expect(find.text('+265'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('country-code-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('country-KE')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('country-search')), 'zam');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('country-ZM')), findsOneWidget);
      expect(find.byKey(const ValueKey('country-KE')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('country-ZM')));
      await tester.pumpAndSettle();
      expect(picked?.iso, 'ZM');
    });
  });

  group('sign up', () {
    test('the payload carries only the required fields, plus username and Terms', () {
      final body = AuthRepository.registerBody(
        phoneNumber: '+265991234567',
        email: ' chikondi@example.com ',
        password: 'secret123',
        username: 'chikondi',
        acceptedTerms: true,
      );
      expect(body, {
        'phone_number': '+265991234567',
        'email': 'chikondi@example.com',
        'password': 'secret123',
        'username': 'chikondi',
        'accepted_terms': true,
      });
      for (final gone in ['first_name', 'last_name', 'password_confirmation', 'income_bracket', 'middle_name']) {
        expect(body.containsKey(gone), isFalse, reason: gone);
      }
    });

    test('an empty username is left out for the server to choose', () {
      final body = AuthRepository.registerBody(phoneNumber: '+265881', email: 'a@b.mw', password: 'x', username: ' ');
      expect(body.keys, unorderedEquals(['phone_number', 'email', 'password']));
    });

    test('the username suggestion comes from the email', () {
      expect(suggestUsername('Chikondi.Banda+mw@example.com'), 'chikondi.banda');
      expect(suggestUsername('tk'), 'tk');
    });

    testWidgets('one screen, no names and no SMS code; a foreign number explains AI reading', (tester) async {
      await _pumpLocalized(tester, const RegisterScreen());
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('First name'), findsNothing);
      expect(find.textContaining('code', findRichText: true), findsNothing);
      expect(find.byKey(const ValueKey('signup-foreign-notice')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('signup-email')), 'chikondi@example.com');
      await tester.pump();
      expect(
        tester.widget<TextFormField>(find.byKey(const ValueKey('signup-username'))).controller!.text,
        'chikondi',
      );

      await tester.tap(find.byKey(const ValueKey('country-code-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('country-ZA')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('signup-foreign-notice')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('sender to account mapping', () {
    test('known senders map to wallet and bank accounts', () {
      expect(suggestedAccountFor('AirtelMoney'), (name: 'Airtel Money', type: 'mobile_money'));
      expect(suggestedAccountFor('MPAMBA'), (name: 'TNM Mpamba', type: 'mobile_money'));
      expect(suggestedAccountFor('NBM')?.type, 'bank');
      expect(suggestedAccountFor('FDH Bank')?.name, 'FDH Bank');
      expect(suggestedAccountFor('CenteBank')?.name, 'Centenary Bank');
      expect(suggestedAccountFor('RandomBank'), isNull);
      expect(suggestedAccountFor(null), isNull);
    });

    test('only missing accounts are created, once each', () {
      final toCreate = accountsToCreate(
        ['AirtelMoney', 'AirtelMoney', 'NBM', 'MPAMBA', 'Unknown', null],
        [_account('My Airtel', 'mobile_money')],
      );
      expect(toCreate, [(name: 'NBM', type: 'bank'), (name: 'TNM Mpamba', type: 'mobile_money')]);
    });

    test('messages are counted per sender, most first', () {
      final rows = countBySender(['MPAMBA', 'AirtelMoney', 'TNM', '+265999']);
      expect(rows.first.label, 'TNM Mpamba');
      expect(rows.first.count, 2);
      expect(rows.map((r) => r.label), containsAll(['Airtel Money', '+265999']));
    });

    test('the import window is 30 days, never before the server baseline', () {
      final now = DateTime(2026, 11, 21);
      expect(FirstRunImport.startFrom(now, null), DateTime(2026, 10, 22));
      expect(FirstRunImport.startFrom(now, DateTime(2026, 1, 1)), DateTime(2026, 10, 22));
      expect(FirstRunImport.startFrom(now, DateTime(2026, 11, 20)), DateTime(2026, 11, 20));
    });
  });

  group('home first visit', () {
    testWidgets('greets without "Welcome back" on the first visit', (tester) async {
      await _pumpLocalized(
        tester,
        Builder(builder: (_) => Text(homeGreeting(firstName: 'Chikondi', firstVisit: true))),
      );
      expect(find.text('Hi Chikondi'), findsOneWidget);
      expect(find.textContaining('Welcome back'), findsNothing);
      // Signup no longer asks for a name: a neutral greeting.
      expect(homeGreeting(firstName: '', firstVisit: true), 'Hi');
      expect(homeGreeting(firstName: null, firstVisit: true), 'Hi');
      // Later visits keep the returning greeting.
      expect(homeGreeting(firstName: 'Chikondi', firstVisit: false), 'Welcome back, Chikondi');
    });

    test('the 30-day summary adds money in and spending out by category', () {
      Txn t(String id, String type, int major, {String? cat, bool spending = true}) => Txn.fromJson({
        'id': id,
        'type': type,
        'amount': _m(major),
        'category': cat == null ? null : {'id': cat, 'name': cat, 'is_spending': spending},
      });
      final summary = summarisePeriod([
        t('1', 'income', 50000),
        t('2', 'expense', 3000, cat: 'Food'),
        t('3', 'expense', 7000, cat: 'Transport'),
        t('4', 'expense', 2000, cat: 'Food'),
        t('5', 'expense', 9000, cat: 'Savings', spending: false),
        t('6', 'transfer', 4000),
        t('7', 'expense', 1000),
      ], uncategorised: 'No category yet');
      expect(summary.moneyIn.minorUnits, 5000000);
      expect(summary.moneyOut.minorUnits, 1300000);
      expect(summary.moneyOut.formatted, 'MK 13,000.00');
      expect(summary.topCategories.map((c) => c.name), ['Transport', 'Food', 'No category yet']);
      expect(summary.topCategories[1].amount.minorUnits, 500000);
    });
  });
}
