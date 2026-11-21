import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/money/money_json.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/subscription_models.dart';
import '../paywall_prompt.dart';
import '../screens/pricing_screen.dart';
import '../upgrade_flow.dart';
import 'limit_reached_sheet.dart';
import 'subscription_status_tile.dart';
import 'trial_sheets.dart';

/// Old callers pass a plain feature label; map the ones we know.
const _legacyFeatureEntitlements = {'SMS auto-capture': smsCaptureEntitlement};

/// The one entry point for every premium wall and "upgrade" button.
///
///  * The free SMS allowance is used up: the limit sheet (Day pass for the
///    waiting messages, or all passes).
///  * A free user who never had a trial: the first premium tap starts the free
///    trial and carries on into the feature. When the app (not a tap) hit the
///    wall, [automatic] is true and the trial is offered, not started.
///  * Everyone else: the pricing screen.
///
/// Returns true when the person came back with premium on.
/// [entitlement] picks the headline (what this feature does for them);
/// [feature] is an older plain label, mapped when known.
/// [surface] names where it was opened from, for funnel analytics.
/// [limitReached] says the server just refused an SMS for the allowance.
Future<bool> showPaywall(
  BuildContext context, {
  String? feature,
  String? entitlement,
  String surface = 'unknown',
  bool limitReached = false,
  bool automatic = false,
}) async {
  final resolvedEntitlement =
      entitlement ?? _legacyFeatureEntitlements[feature];
  final trackProps = <String, Object?>{
    'surface': surface,
    'entitlement': resolvedEntitlement,
  };
  Analytics.track('upgrade_prompt_viewed', trackProps);
  // Opened from a locked feature (not the subscription screen or the trial
  // banner): record which feature drew the tap.
  if (resolvedEntitlement != null) {
    Analytics.track('premium_feature_tapped', {'feature': resolvedEntitlement, 'surface': surface});
  }

  final container = ProviderScope.containerOf(context, listen: false);
  PaywallPrompter.instance.sheetOpened();
  var result = false;
  try {
    if (resolvedEntitlement == smsCaptureEntitlement) {
      final sub = container.read(currentUserProvider)?.subscription ?? const SubscriptionInfo.none();
      final sms = sub.smsCapture;
      final usedUp = limitReached ||
          (!sub.active && sms != null && sms.isLimited && smsCapturesRemaining(sms) == 0);
      result = usedUp
          ? await showLimitReachedSheet(context, surface: surface)
          : await openPricing(context, entitlement: resolvedEntitlement, surface: surface);
    } else {
      final sub = await currentSubscriptionForUpgrade(container);
      if (!context.mounted) return false;
      result = upgradeRouteFor(sub) == UpgradeRoute.trial
          ? await _trialFirst(context, container, sub,
              entitlement: resolvedEntitlement, surface: surface, automatic: automatic)
          : await openPricing(context, entitlement: resolvedEntitlement, surface: surface);
    }
  } finally {
    PaywallPrompter.instance.sheetClosed();
  }

  if (!result) Analytics.track('paywall_dismissed', trackProps);
  return result;
}

/// Start the free trial (asking first when [automatic]), then confirm it.
/// Falls back to pricing when the server says no trial is left.
Future<bool> _trialFirst(
  BuildContext context,
  ProviderContainer container,
  SubscriptionInfo sub, {
  String? entitlement,
  required String surface,
  required bool automatic,
}) async {
  if (automatic) {
    final choice = await showTrialOfferSheet(context, days: sub.trialDays, entitlement: entitlement);
    if (choice == null || !context.mounted) return false;
    if (choice == TrialOfferChoice.pricing) {
      return openPricing(context, entitlement: entitlement, surface: surface);
    }
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  ));
  final started = await startFreeTrial(container);
  navigator.pop();
  if (!context.mounted) return started == TrialStartResult.started;

  switch (started) {
    case TrialStartResult.started:
      await showTrialStartedSheet(context, days: sub.trialDays);
      return true;
    case TrialStartResult.unavailable:
      return openPricing(context, entitlement: entitlement, surface: surface);
    case TrialStartResult.failed:
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('upgrade.trial.failed'.tr())));
      return false;
  }
}

/// Hours left on an active free trial (at least 1), or null when not on one.
int? trialHoursLeft(SubscriptionInfo sub, DateTime now) {
  final ends = sub.endsAt;
  if (!sub.active || !sub.isTrial || ends == null || !ends.isAfter(now)) {
    return null;
  }
  final minutes = ends.difference(now).inMinutes;
  return minutes <= 60 ? 1 : (minutes / 60).ceil();
}

/// What a cell of the comparison shows.
enum Availability { included, notIncluded, note }

/// One row of the Free vs Premium comparison.
class ComparisonRow {
  const ComparisonRow(
    this.labelKey,
    this.free,
    this.premium, {
    this.freeNoteKey,
    this.premiumNoteKey,
  });

  final String labelKey;
  final Availability free;
  final Availability premium;
  final String? freeNoteKey;
  final String? premiumNoteKey;
}

/// The comparison, mirroring what the server enforces (config/subscriptions.php).
const paywallComparisonRows = <ComparisonRow>[
  ComparisonRow(
    'paywall.compare.manual',
    Availability.included,
    Availability.included,
  ),
  ComparisonRow(
    'paywall.compare.balances',
    Availability.included,
    Availability.included,
  ),
  ComparisonRow(
    'paywall.compare.budgetsGoals',
    Availability.included,
    Availability.included,
  ),
  ComparisonRow(
    'paywall.compare.smsCapture',
    Availability.note,
    Availability.note,
    freeNoteKey: 'paywall.compare.smsFree',
    premiumNoteKey: 'paywall.compare.unlimited',
  ),
  ComparisonRow(
    'paywall.compare.coach',
    Availability.notIncluded,
    Availability.included,
  ),
  ComparisonRow(
    'paywall.compare.insights',
    Availability.notIncluded,
    Availability.included,
  ),
  ComparisonRow(
    'paywall.compare.aiReading',
    Availability.notIncluded,
    Availability.included,
  ),
  ComparisonRow(
    'paywall.compare.offline',
    Availability.notIncluded,
    Availability.note,
    premiumNoteKey: 'paywall.compare.offlineNote',
  ),
  ComparisonRow(
    'paywall.compare.exports',
    Availability.note,
    Availability.note,
    freeNoteKey: 'paywall.compare.exportsFree',
    premiumNoteKey: 'paywall.compare.exportsPremium',
  ),
];

/// Free vs Premium table.
class PaywallComparison extends StatelessWidget {
  const PaywallComparison({super.key, this.freeSmsLimit});

  /// The free monthly allowance from the API; null until it has loaded.
  final int? freeSmsLimit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 13,
      color: scheme.onSurface,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: SizedBox.shrink()),
              SizedBox(
                width: 84,
                child: Text(
                  'paywall.compare.free'.tr(),
                  textAlign: TextAlign.center,
                  style: header,
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  'paywall.compare.premium'.tr(),
                  textAlign: TextAlign.center,
                  style: header.copyWith(color: scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final row in paywallComparisonRows)
            Padding(
              key: ValueKey('compare-${row.labelKey}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.labelKey.tr(),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: _Cell(
                      row.free,
                      row.freeNoteKey,
                      limit: freeSmsLimit,
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: _Cell(
                      row.premium,
                      row.premiumNoteKey,
                      limit: freeSmsLimit,
                      premium: true,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.availability,
    this.noteKey, {
    required this.limit,
    this.premium = false,
  });

  final Availability availability;
  final String? noteKey;
  final int? limit;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (availability) {
      Availability.included => Icon(
        Icons.check_circle,
        size: 18,
        color: premium ? scheme.primary : scheme.onSurfaceVariant,
        semanticLabel: 'paywall.compare.included'.tr(),
      ),
      Availability.notIncluded => Icon(
        Icons.remove,
        size: 18,
        color: scheme.outline,
        semanticLabel: 'paywall.compare.notIncluded'.tr(),
      ),
      Availability.note => Text(
        limit == null && noteKey == 'paywall.compare.smsFree'
            ? 'paywall.compare.smsFreeMonthly'.tr()
            : (noteKey ?? '').tr(namedArgs: {'limit': '${limit ?? ''}'}),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: premium ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    };
  }
}

/// "MK 398/day": the per-day price, rounded to whole units ("≈" when rounded).
String perDayPriceLabel(PlanOption plan) {
  final days = plan.days <= 0 ? 1 : plan.days;
  final perDay = plan.amount.amount / days;
  final rounded = perDay.roundToDouble();
  final label = formatMoney(
    rounded,
    plan.amount.currency,
  ).replaceFirst(RegExp(r'\.00$'), '');
  return (rounded == perDay ? '' : '≈ ') + label;
}
