import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/network/api_exception.dart';
import 'package:mulinda_mobile/features/auth/data/user.dart';
import 'package:mulinda_mobile/features/auth/providers/auth_controller.dart';
import 'package:mulinda_mobile/features/subscription/checkout_flow.dart';
import 'package:mulinda_mobile/features/subscription/data/subscription_models.dart';
import 'package:mulinda_mobile/features/subscription/paywall_prompt.dart';
import 'package:mulinda_mobile/features/subscription/widgets/paywall_sheet.dart';
import 'package:mulinda_mobile/features/subscription/widgets/subscription_status_tile.dart';
import 'package:mulinda_mobile/features/subscription/widgets/trial_banner.dart';

User _user(SubscriptionInfo sub) => User(
  id: 'u1',
  firstName: 'Test',
  lastName: 'User',
  username: 'test',
  email: 't@example.com',
  fullName: 'Test User',
  subscription: sub,
);

SmsCaptureInfo _sms({
  required int used,
  required int limit,
  required int remaining,
}) => SmsCaptureInfo(
  used: used,
  limit: limit,
  remaining: remaining,
  usagePercentage: 0,
  isLimited: true,
);

InvoiceModel _invoice(String status) => InvoiceModel(
  id: 'inv',
  period: 'week',
  periodLabel: 'Weekly',
  amount: const MoneyView(
    minorUnits: 250000,
    currency: 'MWK',
    amount: 2500,
    formatted: 'MK 2,500.00',
  ),
  currency: 'MWK',
  status: status,
  txRef: 'tx',
  isResumable: status == 'pending' || status == 'failed',
);

Widget _host(Widget child, {User? user}) => ProviderScope(
  overrides: [currentUserProvider.overrideWithValue(user)],
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('402 → paywall', () {
    test('subscription_required carries the locked entitlement', () {
      expect(
        paywallTriggerFor(402, {
          'code': 'subscription_required',
          'entitlement': 'coach.chat',
        }),
        const PaywallTrigger(
          code: 'subscription_required',
          entitlement: 'coach.chat',
        ),
      );
    });

    test('the SMS capture limit maps to the SMS allowance', () {
      expect(
        paywallTriggerFor(402, {
          'code': 'sms_capture_limit_reached',
        })?.entitlement,
        smsCaptureEntitlement,
      );
    });

    test(
      'other 402s (an export awaiting its one-time payment) and other statuses are left alone',
      () {
        expect(
          paywallTriggerFor(402, {
            'data': {'status': 'pending_payment'},
          }),
          isNull,
        );
        expect(
          paywallTriggerFor(403, {'code': 'subscription_required'}),
          isNull,
        );
        expect(paywallTriggerFor(402, 'not json'), isNull);
      },
    );

    test('each entitlement gets its own benefit headline', () {
      expect(paywallHeadlineKey('coach.chat'), 'paywall.headline.coachChat');
      expect(
        paywallHeadlineKey('insights.advanced'),
        'paywall.headline.insights',
      );
      expect(paywallHeadlineKey('capture.ai'), 'paywall.headline.aiCapture');
      expect(
        paywallHeadlineKey(smsCaptureEntitlement),
        'paywall.headline.smsCapture',
      );
      expect(paywallHeadlineKey('unknown'), 'paywall.headline.default');
    });

    test(
      'reads open the sheet, writes only offer a snackbar, and prompts are debounced',
      () {
        var now = DateTime(2026, 11, 5, 10);
        final prompter = PaywallPrompter(clock: () => now);
        const t = PaywallTrigger(
          code: 'subscription_required',
          entitlement: 'coach.chat',
        );

        expect(prompter.handle(t, method: 'GET'), PaywallPresentation.sheet);
        expect(
          prompter.handle(t, method: 'GET'),
          isNull,
        ); // within the cooldown

        now = now.add(const Duration(minutes: 1));
        expect(
          prompter.handle(t, method: 'POST'),
          PaywallPresentation.snackbar,
        );
      },
    );

    test(
      'never during a save the screen is handling, nor over an open paywall',
      () async {
        final prompter = PaywallPrompter(cooldown: Duration.zero);
        const t = PaywallTrigger(
          code: 'sms_capture_limit_reached',
          entitlement: smsCaptureEntitlement,
        );

        PaywallPresentation? during;
        await prompter.guardSave(
          () async => during = prompter.handle(t, method: 'POST'),
        );
        expect(during, isNull);

        prompter.sheetOpened();
        expect(prompter.handle(t, method: 'GET'), isNull);
        prompter.sheetClosed();
        expect(prompter.handle(t, method: 'GET'), PaywallPresentation.sheet);
      },
    );
  });

  group('paywall', () {
    testWidgets('shows every Free vs Premium row', (tester) async {
      await tester.pumpWidget(_host(const PaywallComparison()));

      for (final row in paywallComparisonRows) {
        expect(find.byKey(ValueKey('compare-${row.labelKey}')), findsOneWidget);
      }
      expect(
        paywallComparisonRows.map((r) => r.labelKey),
        containsAll([
          'paywall.compare.manual',
          'paywall.compare.smsCapture',
          'paywall.compare.coach',
          'paywall.compare.offline',
          'paywall.compare.exports',
        ]),
      );
    });

    test('free keeps core tracking; AI features are premium only', () {
      final byKey = {for (final r in paywallComparisonRows) r.labelKey: r};
      for (final key in [
        'paywall.compare.manual',
        'paywall.compare.balances',
        'paywall.compare.budgetsGoals',
      ]) {
        expect(byKey[key]!.free, Availability.included);
      }
      for (final key in [
        'paywall.compare.coach',
        'paywall.compare.insights',
        'paywall.compare.aiReading',
      ]) {
        expect(byKey[key]!.free, Availability.notIncluded);
        expect(byKey[key]!.premium, Availability.included);
      }
    });

    test('per-day price is the total divided by the days', () {
      PlanOption plan(int days, double amount) => PlanOption(
        period: 'p$days',
        label: 'P',
        days: days,
        amount: MoneyView(
          minorUnits: (amount * 100).round(),
          currency: 'MWK',
          amount: amount,
          formatted: '',
        ),
      );
      expect(perDayPriceLabel(plan(1, 500)), 'MK 500');
      expect(perDayPriceLabel(plan(30, 10500)), 'MK 350');
      expect(perDayPriceLabel(plan(3, 1195)), '≈ MK 398');
    });

    test('trial hours left are honest and hidden when not on a trial', () {
      final now = DateTime.utc(2026, 11, 5, 10);
      final trial = SubscriptionInfo(
        active: true,
        isTrial: true,
        endsAt: now.add(const Duration(hours: 5, minutes: 10)),
      );
      expect(trialHoursLeft(trial, now), 6);
      expect(
        trialHoursLeft(
          SubscriptionInfo(
            active: true,
            isTrial: true,
            endsAt: now.add(const Duration(minutes: 20)),
          ),
          now,
        ),
        1,
      );
      expect(
        trialHoursLeft(
          SubscriptionInfo(
            active: true,
            isTrial: false,
            endsAt: now.add(const Duration(days: 2)),
          ),
          now,
        ),
        isNull,
      );
      expect(
        trialHoursLeft(
          SubscriptionInfo(
            active: true,
            isTrial: true,
            endsAt: now.subtract(const Duration(hours: 1)),
          ),
          now,
        ),
        isNull,
      );
    });
  });

  group('checkout outcome', () {
    Future<CheckoutOutcome> resolve(
      CheckoutExit exit,
      List<Object> verifyAnswers, {
      String cancelStatus = 'cancelled',
    }) {
      var i = 0;
      return resolveCheckout(
        exit: exit,
        retryDelay: Duration.zero,
        verify: () async {
          final answer = verifyAnswers[i < verifyAnswers.length - 1 ? i++ : i];
          if (answer is ApiException) throw answer;
          return _invoice(answer as String);
        },
        cancel: () async => _invoice(cancelStatus),
      );
    }

    test('a return is only a success when the server says paid', () async {
      expect(
        await resolve(CheckoutExit.returned, ['pending', 'paid']),
        CheckoutOutcome.paid,
      );
      expect(
        await resolve(CheckoutExit.returned, ['failed']),
        CheckoutOutcome.failed,
      );
      expect(
        await resolve(CheckoutExit.returned, ['pending']),
        CheckoutOutcome.pending,
      );
      expect(
        await resolve(CheckoutExit.returned, [
          ApiException('down', statusCode: 502),
        ]),
        CheckoutOutcome.pending,
      );
    });

    test(
      'closing checkout cancels a still-open invoice, but a completed payment still counts',
      () async {
        expect(
          await resolve(CheckoutExit.closed, ['pending']),
          CheckoutOutcome.cancelled,
        );
        expect(
          await resolve(CheckoutExit.closed, ['paid']),
          CheckoutOutcome.paid,
        );
        expect(
          await resolve(CheckoutExit.closed, ['failed']),
          CheckoutOutcome.failed,
        );
      },
    );

    test('messages match the outcome', () {
      expect(
        checkoutOutcomeMessageKey(CheckoutOutcome.paid),
        'paywall.checkout.paid',
      );
      expect(
        checkoutOutcomeMessageKey(CheckoutOutcome.failed),
        'paywall.checkout.failed',
      );
      expect(
        checkoutOutcomeMessageKey(CheckoutOutcome.pending),
        'paywall.checkout.pending',
      );
      expect(
        checkoutOutcomeMessageKey(CheckoutOutcome.cancelled),
        'paywall.checkout.cancelled',
      );
    });
  });

  group('status tile and trial banner', () {
    test('free SMS captures left never go below zero', () {
      expect(smsCapturesRemaining(_sms(used: 3, limit: 10, remaining: 7)), 7);
      expect(smsCapturesRemaining(_sms(used: 14, limit: 10, remaining: 10)), 0);
      expect(smsCapturesRemaining(_sms(used: 0, limit: 10, remaining: -4)), 0);
      expect(smsCapturesRemaining(_sms(used: 0, limit: -1, remaining: 3)), 0);
      expect(smsCapturesRemaining(null), 0);
    });

    testWidgets('the tile renders for a free user who is over the limit', (
      tester,
    ) async {
      final user = _user(
        SubscriptionInfo(
          active: false,
          smsCapture: _sms(used: 12, limit: 10, remaining: 0),
        ),
      );
      await tester.pumpWidget(
        _host(const SubscriptionStatusTile(), user: user),
      );

      expect(
        find.byKey(const ValueKey('subscription-status-tile')),
        findsOneWidget,
      );
      expect(find.textContaining('-'), findsNothing);
    });

    testWidgets('the trial banner shows only during a trial', (tester) async {
      final onTrial = _user(
        SubscriptionInfo(
          active: true,
          isTrial: true,
          endsAt: DateTime.now().add(const Duration(hours: 3)),
        ),
      );
      await tester.pumpWidget(_host(const TrialBanner(), user: onTrial));
      expect(find.byKey(const ValueKey('trial-banner')), findsOneWidget);

      final paid = _user(
        SubscriptionInfo(
          active: true,
          isTrial: false,
          endsAt: DateTime.now().add(const Duration(days: 3)),
        ),
      );
      await tester.pumpWidget(_host(const TrialBanner(), user: paid));
      expect(find.byKey(const ValueKey('trial-banner')), findsNothing);

      await tester.pumpWidget(_host(const TrialBanner()));
      expect(find.byKey(const ValueKey('trial-banner')), findsNothing);
    });
  });

  test('every key the growth screens use exists in English and Chichewa', () {
    Object? lookup(Map<String, dynamic> tree, String key) {
      Object? node = tree;
      for (final part in key.split('.')) {
        node = node is Map ? node[part] : null;
      }
      return node;
    }

    final keys = <String>{
      for (final r in paywallComparisonRows) ...[
        r.labelKey,
        ?r.freeNoteKey,
        ?r.premiumNoteKey,
      ],
      for (final e in [
        'coach.chat',
        'coach.history',
        'insights.advanced',
        'capture.ai',
        'offline.mode',
        smsCaptureEntitlement,
        null,
      ])
        paywallHeadlineKey(e),
      for (final o in CheckoutOutcome.values) checkoutOutcomeMessageKey(o),
      'paywall.title',
      'paywall.seePlans',
      'paywall.choosePass',
      'paywall.noAutoRenew',
      'paywall.trialNote',
      'paywall.compare.free',
      'paywall.compare.premium',
      'paywall.plan.oneDay',
      'paywall.plan.days',
      'paywall.plan.perDay',
      'paywall.plan.total',
      'paywall.plan.lowestPerDay',
      'paywall.plan.includesOffline',
      'paywall.checkout.title',
      'paywall.checkout.retry',
      'paywall.checkout.leaveTitle',
      'paywall.checkout.leaveBody',
      'paywall.checkout.stay',
      'paywall.checkout.leave',
      'subscription.tile.free',
      'subscription.tile.freeSms',
      'subscription.tile.trialEnds',
      'subscription.tile.activeUntil',
      'subscription.trialBanner.title',
      'subscription.trialBanner.body',
      'subscription.sms.remaining',
      'subscription.sms.freeIntro',
      'subscription.sms.usedUp',
      'subscription.sms.howItWorks',
      'onboarding.trial.title',
      'onboarding.trial.body',
    };

    for (final lang in ['en', 'ny']) {
      final tree =
          jsonDecode(File('assets/translations/$lang.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final key in keys) {
        expect(
          lookup(tree, key),
          isA<String>(),
          reason: '$lang is missing $key',
        );
      }
    }
  });
}
