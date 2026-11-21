import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money_json.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/providers/auth_controller.dart';
import '../checkout_flow.dart';
import '../data/subscription_models.dart';
import '../data/subscription_repository.dart';
import '../paywall_prompt.dart';
import '../upgrade_flow.dart';
import '../widgets/paywall_sheet.dart';

/// Open the pricing screen above everything. Returns true when the person
/// came back with a paid pass.
Future<bool> openPricing(BuildContext context, {String? entitlement, String surface = 'unknown'}) async {
  final paid = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(builder: (_) => PricingScreen(entitlement: entitlement, surface: surface)),
  );
  return paid ?? false;
}

/// "Choose your pass": the visible passes from the API except the Day pass,
/// the best value one selected, then PayChangu's hosted checkout. Coming back
/// without paying shows "Payment not completed" here.
class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key, this.entitlement, this.surface = 'unknown'});

  /// The locked feature that led here, for the headline.
  final String? entitlement;
  final String surface;

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  String? _selected;
  bool _busy = false;
  String? _unpaidKey;

  Future<void> _pay(PlanOption plan) async {
    setState(() {
      _busy = true;
      _unpaidKey = null;
    });
    final outcome = await purchasePass(context, ref, period: plan.period, surface: widget.surface);
    if (!mounted) return;
    if (outcome == CheckoutOutcome.paid) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _unpaidKey = unpaidMessageKey(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final plansAsync = ref.watch(plansProvider);
    final sub = ref.watch(currentUserProvider)?.subscription ?? const SubscriptionInfo.none();
    final plans = pricingPlans(plansAsync.valueOrNull ?? const []);
    final best = bestValuePeriod(plans);
    final selected = plans.where((p) => p.period == (_selected ?? best)).firstOrNull ??
        (plans.isEmpty ? null : plans.last);

    return Scaffold(
      appBar: AppBar(title: Text('upgrade.pricing.title'.tr())),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorRetry(
            message: e is ApiException ? e.displayMessage : 'subscription.plansError'.tr(),
            onRetry: () => ref.invalidate(plansProvider),
          ),
        ),
        data: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xl),
          children: [
            Text(
              paywallHeadlineKey(widget.entitlement).tr(),
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (trialHoursLeft(sub, DateTime.now()) != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'upgrade.pricing.onTrial'.tr(),
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final plan in plans) ...[
              PassOptionCard(
                plan: plan,
                selected: plan.period == selected?.period,
                bestValue: plan.period == best,
                onTap: _busy ? null : () => setState(() => _selected = plan.period),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_unpaidKey != null) ...[
              _UnpaidBanner(messageKey: _unpaidKey!),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              'upgrade.pricing.howToPay'.tr(),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader('upgrade.pricing.compareTitle'.tr()),
            PaywallComparison(freeSmsLimit: sub.smsCapture?.limit),
          ],
        ),
      ),
      bottomNavigationBar: selected == null
          ? null
          : BottomActionBar(
              style: BottomActionBar.ctaButtonStyle(context),
              onPressed: _busy ? null : () => _pay(selected),
              label: _busy
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onSecondary),
                    )
                  : Text(
                      'upgrade.pricing.continue'.tr(namedArgs: {
                        'amount': formatMinorShort(selected.amount.minorUnits, selected.amount.currency),
                      }),
                    ),
            ),
    );
  }
}

/// One pass on the pricing screen: name, days and price per day, total price.
class PassOptionCard extends StatelessWidget {
  const PassOptionCard({
    super.key,
    required this.plan,
    required this.selected,
    required this.bestValue,
    required this.onTap,
  });

  final PlanOption plan;
  final bool selected;
  final bool bestValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = plan.days == 1
        ? 'paywall.plan.oneDay'.tr()
        : 'paywall.plan.days'.tr(namedArgs: {'days': '${plan.days}'});

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        key: ValueKey('pass-${plan.period}'),
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              plan.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                              ),
                            ),
                            if (bestValue)
                              StatusChip(label: 'upgrade.pricing.bestValue'.tr(), tone: StatusTone.warning),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '$days · ${'paywall.plan.perDay'.tr(namedArgs: {'price': perDayPriceLabel(plan)})}',
                          style: TextStyle(
                            fontSize: 13,
                            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    formatMinorShort(plan.amount.minorUnits, plan.amount.currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnpaidBanner extends StatelessWidget {
  const _UnpaidBanner({required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    return Container(
      key: const ValueKey('pricing-unpaid'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: s.warningContainer, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: s.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              messageKey.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
