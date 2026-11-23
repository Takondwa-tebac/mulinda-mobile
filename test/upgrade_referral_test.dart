import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/auth/data/auth_repository.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/referral/data/referral_capture.dart';
import 'package:mulinda_mobile/features/referral/data/referral_repository.dart';
import 'package:mulinda_mobile/features/referral/screens/referral_screen.dart';
import 'package:mulinda_mobile/features/subscription/checkout_flow.dart';
import 'package:mulinda_mobile/features/subscription/data/home_alert_dismissals.dart';
import 'package:mulinda_mobile/features/subscription/data/subscription_models.dart';
import 'package:mulinda_mobile/features/subscription/upgrade_flow.dart';
import 'package:mulinda_mobile/features/subscription/widgets/top_up_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanOption _plan(String period, int days, int minor) => PlanOption(
  period: period,
  label: period,
  days: days,
  amount: MoneyView(minorUnits: minor, currency: 'MWK', amount: minor / 100, formatted: ''),
);

User _user(SubscriptionInfo sub) => User(
  id: 'u1',
  firstName: 'Test',
  lastName: 'User',
  username: 'test',
  email: 't@example.com',
  fullName: 'Test User',
  subscription: sub,
);

void main() {
  group('trial or pricing', () {
    test('a free user with a trial available gets the trial', () {
      expect(
        upgradeRouteFor(const SubscriptionInfo(active: false, trialAvailable: true, trialDays: 7)),
        UpgradeRoute.trial,
      );
    });

    test('no trial left, unknown, or already premium: pricing', () {
      expect(upgradeRouteFor(const SubscriptionInfo(active: false, trialAvailable: false)), UpgradeRoute.pricing);
      expect(upgradeRouteFor(const SubscriptionInfo(active: false)), UpgradeRoute.pricing);
      expect(upgradeRouteFor(const SubscriptionInfo(active: true, trialAvailable: true)), UpgradeRoute.pricing);
    });

    test('the summary reads trial and top-up fields from the API', () {
      final sub = SubscriptionInfo.fromJson({
        'active': true,
        'trial_available': false,
        'trial_days': 7,
        'top_up': {'period': 'week', 'amount_minor': 100000, 'currency': 'MWK'},
      });
      expect(sub.trialAvailable, isFalse);
      expect(sub.trialDays, 7);
      expect(sub.topUp?.amountMinor, 100000);
      expect(SubscriptionInfo.fromJson({'active': false}).trialAvailable, isNull);
      expect(SubscriptionInfo.fromJson({'active': true, 'top_up': null}).topUp, isNull);
    });
  });

  group('pricing', () {
    final all = [_plan('day', 1, 50000), _plan('week', 7, 150000), _plan('month', 30, 450000)];

    test('lists every visible plan except the Day pass', () {
      expect(pricingPlans(all).map((p) => p.period), ['week', 'month']);
      expect(dayPassPlan(all)?.period, 'day');
    });

    test('falls back to the Day pass when it is the only plan', () {
      expect(pricingPlans([_plan('day', 1, 50000)]).map((p) => p.period), ['day']);
    });

    test('the month is best value by price per day', () {
      expect(bestValuePeriod(pricingPlans(all)), 'month');
      expect(bestValuePeriod([_plan('week', 7, 150000)]), isNull);
    });

    test('closing checkout without paying says nothing was charged', () {
      expect(unpaidMessageKey(CheckoutOutcome.cancelled), 'upgrade.pricing.notCompleted');
      expect(unpaidMessageKey(CheckoutOutcome.paid), isNull);
    });
  });

  group('top-up', () {
    const offer = TopUpOffer(period: 'week', amountMinor: 100000, currency: 'MWK');

    test('visible only with an offer on a running paid pass', () {
      expect(showTopUp(const SubscriptionInfo(active: true, topUp: offer)), isTrue);
      expect(showTopUp(const SubscriptionInfo(active: true)), isFalse);
      expect(showTopUp(const SubscriptionInfo(active: false, topUp: offer)), isFalse);
      expect(showTopUp(const SubscriptionInfo(active: true, isTrial: true, topUp: offer)), isFalse);
      expect(
        showTopUp(const SubscriptionInfo(
          active: true,
          topUp: TopUpOffer(period: 'week', amountMinor: 0, currency: 'MWK'),
        )),
        isFalse,
      );
    });

    testWidgets('the card shows the API amount, and nothing without an offer', (tester) async {
      Widget host(SubscriptionInfo sub) => ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(_user(sub))],
        child: const MaterialApp(home: Scaffold(body: TopUpCard())),
      );

      await tester.pumpWidget(host(const SubscriptionInfo(active: true, topUp: offer)));
      expect(find.byKey(const ValueKey('top-up-card')), findsOneWidget);

      await tester.pumpWidget(host(const SubscriptionInfo(active: true)));
      expect(find.byKey(const ValueKey('top-up-card')), findsNothing);
    });

    testWidgets('the close button puts the offer away for this pass', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ends = DateTime.now().add(const Duration(hours: 10));
      final sub = SubscriptionInfo(active: true, endsAt: ends, topUp: offer);
      Widget host() => ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(_user(sub))],
        child: const MaterialApp(home: Scaffold(body: TopUpCard())),
      );
      await tester.pumpWidget(host());
      await tester.pump();
      final close = find.byKey(const ValueKey('top-up-close'));
      expect(close, findsOneWidget);
      expect(tester.getSize(close).height, greaterThanOrEqualTo(44));

      await tester.tap(close);
      await tester.pump();
      expect(find.byKey(const ValueKey('top-up-card')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(topUpCardDismissedKey('u1', ends)), AlertDismissal.done.index);

      // A fresh start remembers it.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host());
      await tester.pump();
      expect(find.byKey(const ValueKey('top-up-card')), findsNothing);
    });
  });

  group('referral code capture', () {
    test('codes are 6 characters without 0, O, 1 or I', () {
      expect(normalizeReferralCode(' chsm27 '), 'CHSM27');
      expect(normalizeReferralCode('CHISO7'), isNull); // has an O
      expect(normalizeReferralCode('ABC1EF'), isNull);
      expect(normalizeReferralCode('ABCDE'), isNull);
      expect(normalizeReferralCode(null), isNull);
    });

    test('reads the code from an invite link', () {
      expect(referralCodeFromUri(Uri.parse('https://mulinda-api.sukulusmis.africa/i/CHSM27')), 'CHSM27');
      expect(referralCodeFromUri(Uri.parse('https://mulinda-api.sukulusmis.africa/i/chsm27/')), 'CHSM27');
      expect(referralCodeFromUri(Uri.parse('https://mulinda-api.sukulusmis.africa/x/CHSM27')), isNull);
      expect(referralCodeFromUri(Uri.parse('mulinda://reset-password?token=a')), isNull);
    });

    test('reads the code from the Play Install Referrer, encoded or not', () {
      expect(referralCodeFromInstallReferrer('ref=CHSM27'), 'CHSM27');
      expect(referralCodeFromInstallReferrer('ref%3DCHSM27'), 'CHSM27');
      expect(referralCodeFromInstallReferrer('utm_source=google-play&utm_medium=organic'), isNull);
      expect(referralCodeFromInstallReferrer(null), isNull);
    });

    test('the pending code is stored, read back and cleared', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingReferralStore(await SharedPreferences.getInstance());
      expect(store.read(), isNull);
      expect(await store.save('nope'), isFalse);
      expect(await store.save('chsm27'), isTrue);
      expect(store.read(), 'CHSM27');
      await store.clear();
      expect(store.read(), isNull);
    });

    test('the install referrer is read once and never overrides a link', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingReferralStore(await SharedPreferences.getInstance());
      await store.save('LNKK22');
      var reads = 0;
      Future<String?> referrer() async {
        reads++;
        return 'ref=PLAY33';
      }

      await ReferralCapture.checkInstallReferrer(store, readReferrer: referrer);
      await ReferralCapture.checkInstallReferrer(store, readReferrer: referrer);
      expect(reads, 1);
      expect(store.read(), 'LNKK22');

      SharedPreferences.setMockInitialValues({});
      final fresh = PendingReferralStore(await SharedPreferences.getInstance());
      await ReferralCapture.checkInstallReferrer(fresh, readReferrer: referrer);
      expect(fresh.read(), 'PLAY33');
    });

    test('sign-up sends the waiting code as referral_code', () {
      final body = AuthRepository.registerBody(
        phoneNumber: '+265881',
        email: 'a@b.mw',
        password: 'x',
        referralCode: 'CHSM27',
      );
      expect(body['referral_code'], 'CHSM27');
      expect(
        AuthRepository.registerBody(phoneNumber: '+265881', email: 'a@b.mw', password: 'x'),
        isNot(contains('referral_code')),
      );
    });
  });

  group('referral screen', () {
    final info = ReferralInfo.fromJson({
      'code': 'CHSM27',
      'link': 'https://mulinda-api.sukulusmis.africa/i/CHSM27',
      'signed_up': 3,
      'rewarded': 2,
      'days_earned': 14,
      'reward_days': 7,
      'share_text': {'en': 'Join me', 'ny': 'Lowani'},
    });

    test('reads the API payload', () {
      expect(info.waiting, 1);
      expect(info.shareMessage('ny'), 'Lowani');
      expect(info.shareMessage('fr'), 'Join me');
    });

    test('without share_text the app falls back to its own invite copy', () {
      final bare = ReferralInfo.fromJson({'code': 'CHSM27', 'link': 'https://x/i/CHSM27'});
      expect(bare.shareMessageOrNull('ny'), isNull);
      expect(bare.shareMessage('ny'), 'https://x/i/CHSM27');
    });

    test('the fallback invite names mobile money and every supported bank', () {
      for (final lang in ['en', 'ny']) {
        final strings = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        final referral = (strings['referral'] as Map).cast<String, dynamic>();
        for (final key in ['shareFallback', 'shareFallbackNoDays']) {
          final text = referral[key] as String;
          for (final name in [
            'Airtel Money',
            'Mpamba',
            'National Bank',
            'Standard Bank',
            'NBS',
            'FDH',
            'First Capital',
            'Centenary',
            '{link}',
          ]) {
            expect(text, contains(name), reason: '$lang $key');
          }
        }
      }
    });

    for (final dark in [false, true]) {
      testWidgets('shows the score, link and code (${dark ? 'dark' : 'light'})', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
            home: Scaffold(body: ReferralBody(info: info)),
          ),
        );
        expect(find.byKey(const ValueKey('referral-signed-up')), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('14'), findsOneWidget);
        expect(find.byKey(const ValueKey('referral-copy-code')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('every new key exists in English and Chichewa', () {
    final en = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, dynamic>;
    final ny = jsonDecode(File('assets/translations/ny.json').readAsStringSync()) as Map<String, dynamic>;

    List<String> leaves(Map<String, dynamic> m, [String prefix = '']) => [
      for (final e in m.entries)
        if (e.value is Map)
          ...leaves((e.value as Map).cast<String, dynamic>(), '$prefix${e.key}.')
        else
          '$prefix${e.key}',
    ];

    for (final ns in ['upgrade', 'referral']) {
      final enKeys = leaves((en[ns] as Map).cast<String, dynamic>()).toSet();
      final nyKeys = leaves((ny[ns] as Map).cast<String, dynamic>()).toSet();
      expect(nyKeys, enKeys, reason: '$ns keys differ between en and ny');
      final text = jsonEncode(en[ns]) + jsonEncode(ny[ns]);
      expect(text.contains(String.fromCharCode(0x2014)), isFalse, reason: 'no em dashes in $ns copy');
    }
  });
}
