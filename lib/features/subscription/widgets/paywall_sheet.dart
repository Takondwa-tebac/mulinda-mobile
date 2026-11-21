import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/money/money_json.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_controller.dart';
import '../checkout_flow.dart';
import '../data/subscription_models.dart';
import '../data/subscription_repository.dart';
import '../paywall_prompt.dart';

/// Old callers pass a plain feature label; map the ones we know.
const _legacyFeatureEntitlements = {'SMS auto-capture': smsCaptureEntitlement};

/// Show the upsell paywall. Returns true if the user came back subscribed.
///
/// [entitlement] picks the headline (what this feature does for them);
/// [feature] is an already-translated line used when no entitlement is known.
/// [surface] names where it was opened from, for funnel analytics.
Future<bool> showPaywall(
  BuildContext context, {
  String? feature,
  String? entitlement,
  String surface = 'unknown',
}) async {
  final resolvedEntitlement =
      entitlement ?? _legacyFeatureEntitlements[feature];
  final trackProps = <String, Object?>{
    'surface': surface,
    'entitlement': resolvedEntitlement,
  };
  Analytics.track('upgrade_prompt_viewed', trackProps);

  PaywallPrompter.instance.sheetOpened();
  bool? result;
  try {
    result = await showModalBottomSheet<bool>(
      context: context,
      // Above the shell, so the capture button never sits over the paywall.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) => PaywallSheet(
            scrollController: controller,
            entitlement: resolvedEntitlement,
            feature: resolvedEntitlement == null ? feature : null,
            surface: surface,
          ),
        ),
      ),
    );
  } finally {
    PaywallPrompter.instance.sheetClosed();
  }

  if (result != true) Analytics.track('paywall_dismissed', trackProps);
  return result ?? false;
}

/// The paywall content: what the locked feature does, an honest Free vs Premium
/// comparison, the trial status, and each pass with its total and per-day price.
class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({
    super.key,
    this.scrollController,
    this.entitlement,
    this.feature,
    this.surface = 'unknown',
  });

  final ScrollController? scrollController;
  final String? entitlement;
  final String? feature;
  final String surface;

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  String? _busyPeriod;

  Future<void> _subscribe(PlanOption plan) async {
    final sub = ref.read(currentUserProvider)?.subscription;
    Analytics.track('paywall_plan_selected', {
      'period': plan.period,
      'days': plan.days,
      'surface': widget.surface,
      'entitlement': widget.entitlement,
      'trial_active': sub?.isTrial ?? false,
    });

    setState(() => _busyPeriod = plan.period);
    try {
      final invoice = await ref
          .read(subscriptionRepositoryProvider)
          .checkout(plan.period);
      if (!mounted) return;
      final outcome = await runCheckout(context, ref, invoice);
      if (outcome == null || !mounted) return;

      if (outcome == CheckoutOutcome.paid) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.of(context).pop(true);
        messenger?.showSnackBar(
          SnackBar(content: Text('paywall.checkout.paid'.tr())),
        );
        return;
      }
      announceCheckoutOutcome(
        context,
        outcome,
        onRetry: () => _subscribe(plan),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(e.displayMessage),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _busyPeriod = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final plansAsync = ref.watch(plansProvider);
    final sub =
        ref.watch(currentUserProvider)?.subscription ??
        const SubscriptionInfo.none();
    final subtitle = widget.entitlement != null || widget.feature == null
        ? paywallHeadlineKey(widget.entitlement).tr()
        : widget.feature!;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Icon(Icons.workspace_premium, size: 40, color: scheme.primary),
        const SizedBox(height: 12),
        Text(
          'paywall.title'.tr(),
          textAlign: TextAlign.center,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        if (trialHoursLeft(sub, DateTime.now()) case final hours?) ...[
          const SizedBox(height: 14),
          _TrialNote(hours: hours),
        ],
        const SizedBox(height: 16),
        PaywallComparison(freeSmsLimit: sub.smsCapture?.limit ?? 10),
        const SizedBox(height: 20),
        Text(
          'paywall.choosePass'.tr(),
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        plansAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Column(
            children: [
              Text(
                e is ApiException
                    ? e.displayMessage
                    : 'subscription.plansError'.tr(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ref.invalidate(plansProvider),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
          data: (plans) => PlanList(
            plans: plans,
            busyPeriod: _busyPeriod,
            onSelect: _subscribe,
          ),
        ),
        const SizedBox(height: 12),
        _Reassurance(),
      ],
    );
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
  const PaywallComparison({super.key, this.freeSmsLimit = 10});

  final int freeSmsLimit;

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
  final int limit;
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
        (noteKey ?? '').tr(namedArgs: {'limit': '$limit'}),
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

/// "MK 398/day" — the per-day price, rounded to whole units ("≈" when rounded).
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

class PlanList extends StatelessWidget {
  const PlanList({
    super.key,
    required this.plans,
    required this.busyPeriod,
    required this.onSelect,
  });

  final List<PlanOption> plans;
  final String? busyPeriod;
  final void Function(PlanOption) onSelect;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) return const SizedBox.shrink();

    // The cheapest per-day pass is labelled "Lowest price per day" (a fact, not a countdown).
    final bestValue = plans
        .reduce((a, b) => a.perDay <= b.perDay ? a : b)
        .period;

    return Column(
      children: [
        for (final p in plans)
          PlanTile(
            plan: p,
            isBestValue: plans.length > 1 && p.period == bestValue,
            busy: busyPeriod == p.period,
            disabled: busyPeriod != null && busyPeriod != p.period,
            onTap: () => onSelect(p),
          ),
      ],
    );
  }
}

class PlanTile extends StatelessWidget {
  const PlanTile({
    super.key,
    required this.plan,
    required this.isBestValue,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final PlanOption plan;
  final bool isBestValue;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = plan.days == 1
        ? 'paywall.plan.oneDay'.tr()
        : 'paywall.plan.days'.tr(namedArgs: {'days': '${plan.days}'});

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isBestValue
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: disabled || busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          plan.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (isBestValue)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'paywall.plan.lowestPerDay'.tr(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$days · ${'paywall.plan.perDay'.tr(namedArgs: {'price': perDayPriceLabel(plan)})}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    if (plan.days >= 3)
                      Text(
                        'paywall.plan.includesOffline'.tr(),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      plan.amount.formatted,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scheme.primary,
                      ),
                    ),
                    Text(
                      'paywall.plan.total'.tr(),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrialNote extends StatelessWidget {
  const _TrialNote({required this.hours});

  final int hours;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_bottom_rounded,
            color: scheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'paywall.trialNote'.tr(namedArgs: {'hours': '$hours'}),
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reassurance extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'paywall.noAutoRenew'.tr(),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
