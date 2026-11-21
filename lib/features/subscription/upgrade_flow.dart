import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/network/api_exception.dart';
import '../auth/providers/auth_controller.dart';
import 'checkout_flow.dart';
import 'data/device_id.dart';
import 'data/subscription_models.dart';
import 'data/subscription_repository.dart';
import 'screens/pass_confirmation_screen.dart';

/// Where a premium tap leads.
enum UpgradeRoute {
  /// Start the free trial and carry on into the feature.
  trial,

  /// Open the pricing screen.
  pricing,
}

/// First premium tap: a free user who never had a trial gets one; everyone
/// else sees the passes. Only the API decides whether a trial is available.
UpgradeRoute upgradeRouteFor(SubscriptionInfo sub) =>
    !sub.active && sub.trialAvailable == true ? UpgradeRoute.trial : UpgradeRoute.pricing;

/// The Day pass period id in the plan catalogue.
const dayPeriod = 'day';

/// The passes the pricing screen lists: every visible plan except the Day
/// pass (that one is offered at the limit-reached moment). If the catalogue
/// only has a Day pass, it is shown rather than an empty screen.
List<PlanOption> pricingPlans(List<PlanOption> all) {
  final longer = all.where((p) => p.period != dayPeriod).toList();
  return longer.isEmpty ? all : longer;
}

/// The Day pass, if the API offers one.
PlanOption? dayPassPlan(List<PlanOption> all) {
  for (final p in all) {
    if (p.period == dayPeriod) return p;
  }
  return null;
}

/// The plan with the lowest price per day ("Best value"), when there is a
/// choice to make.
String? bestValuePeriod(List<PlanOption> plans) {
  if (plans.length < 2) return null;
  return plans.reduce((a, b) => a.perDay <= b.perDay ? a : b).period;
}

/// Whether to show "Make it a week": only while a pass is running and the API
/// offers a top-up with something left to pay.
bool showTopUp(SubscriptionInfo sub) {
  final offer = sub.topUp;
  return sub.active && !sub.isTrial && offer != null && offer.amountMinor > 0;
}

/// The subscription summary to decide on: the signed-in user's, refreshed from
/// `GET /subscription` when it does not say whether a trial is available.
Future<SubscriptionInfo> currentSubscriptionForUpgrade(ProviderContainer container) async {
  final sub = container.read(currentUserProvider)?.subscription ?? const SubscriptionInfo.none();
  if (sub.active || sub.trialAvailable != null) return sub;
  try {
    return await container.read(subscriptionRepositoryProvider).status();
  } catch (_) {
    return sub;
  }
}

/// The result of asking for the trial.
enum TrialStartResult { started, unavailable, failed }

/// Start the free trial on the server, sending this phone's id. Refreshes the
/// signed-in user so premium features unlock straight away.
Future<TrialStartResult> startFreeTrial(
  ProviderContainer container, {
  Future<String?> Function() deviceId = TrialDeviceId.read,
}) async {
  try {
    await container.read(subscriptionRepositoryProvider).startTrial(deviceId: await deviceId());
    Analytics.track('trial_started', const {});
    await container.read(authControllerProvider.notifier).refresh();
    return TrialStartResult.started;
  } on ApiException catch (e) {
    if (e.statusCode == 409 || e.code == 'trial_unavailable') {
      // Stale "available" flag: make sure the next tap goes to pricing.
      await container.read(authControllerProvider.notifier).refresh();
      return TrialStartResult.unavailable;
    }
    return TrialStartResult.failed;
  }
}

/// Buy a pass (or the Day to Week top-up) through PayChangu's hosted checkout,
/// verify on return, and on success show the confirmation screen. Returns the
/// outcome, or null when checkout could not start (already announced).
Future<CheckoutOutcome?> purchasePass(
  BuildContext context,
  WidgetRef ref, {
  required String period,
  bool topUp = false,
  String surface = 'unknown',
}) async {
  Analytics.track(topUp ? 'top_up_selected' : 'paywall_plan_selected', {'period': period, 'surface': surface});
  try {
    final invoice = await ref.read(subscriptionRepositoryProvider).checkout(period, topUp: topUp);
    if (!context.mounted) return null;
    final outcome = await runCheckout(context, ref, invoice);
    if (outcome == CheckoutOutcome.paid && context.mounted) {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(builder: (_) => PassConfirmationScreen(invoice: invoice, topUp: topUp)),
      );
    }
    return outcome;
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(e.displayMessage), backgroundColor: Theme.of(context).colorScheme.error),
        );
    }
    return null;
  }
}

/// "Payment not completed" style messages for anything but a success.
String? unpaidMessageKey(CheckoutOutcome? outcome) => switch (outcome) {
  CheckoutOutcome.cancelled => 'upgrade.pricing.notCompleted',
  CheckoutOutcome.failed => 'paywall.checkout.failed',
  CheckoutOutcome.pending => 'paywall.checkout.pending',
  _ => null,
};

