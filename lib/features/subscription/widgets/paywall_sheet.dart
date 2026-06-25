import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/subscription_models.dart';
import '../data/subscription_repository.dart';
import '../screens/checkout_webview_screen.dart';

/// Show the upsell paywall. Returns true if the user came back subscribed.
Future<bool> showPaywall(BuildContext context, {String? feature}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) =>
          _PaywallSheet(scrollController: controller, feature: feature),
    ),
  );
  return result ?? false;
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet({required this.scrollController, this.feature});

  final ScrollController scrollController;
  final String? feature;

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  String? _busyPeriod;

  Future<void> _subscribe(PlanOption plan) async {
    setState(() => _busyPeriod = plan.period);
    try {
      final invoice =
          await ref.read(subscriptionRepositoryProvider).checkout(plan.period);

      if (invoice.checkoutUrl == null || !mounted) return;

      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              CheckoutWebViewScreen(checkoutUrl: invoice.checkoutUrl!),
        ),
      );

      if (completed == true && mounted) {
        await _verifyAndClose(invoice.id);
      }
    } on ApiException catch (e) {
      _snack(e.displayMessage, error: true);
    } finally {
      if (mounted) setState(() => _busyPeriod = null);
    }
  }

  Future<void> _verifyAndClose(String invoiceId) async {
    try {
      final settled =
          await ref.read(subscriptionRepositoryProvider).verify(invoiceId);
      if (settled.isPaid) {
        await ref.read(authControllerProvider.notifier).refresh();
        if (mounted) {
          Navigator.of(context).pop(true);
          _snack('subscription.activated'.tr());
        }
        return;
      }
    } on ApiException catch (_) {
      // Verification not ready — the webhook/poller will settle it shortly.
    }
    _snack('subscription.pendingVerify'.tr());
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plansAsync = ref.watch(plansProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Icon(Icons.workspace_premium, size: 40, color: scheme.primary),
        const SizedBox(height: 12),
        Text('subscription.paywallTitle'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          widget.feature ?? 'subscription.paywallSubtitle'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _BenefitsCard(),
        const SizedBox(height: 20),
        plansAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Column(
            children: [
              Text(e is ApiException ? e.displayMessage : 'subscription.plansError'.tr(),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ref.invalidate(plansProvider),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
          data: (plans) => _PlanList(
            plans: plans,
            busyPeriod: _busyPeriod,
            onSelect: _subscribe,
          ),
        ),
      ],
    );
  }
}

class _PlanList extends StatelessWidget {
  const _PlanList({
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

    // Cheapest per-day plan is the "best value" anchor.
    final bestValue = plans
        .reduce((a, b) => a.perDay <= b.perDay ? a : b)
        .period;

    return Column(
      children: plans
          .map((p) => _PlanTile(
                plan: p,
                isBestValue: p.period == bestValue,
                busy: busyPeriod == p.period,
                disabled: busyPeriod != null && busyPeriod != p.period,
                onTap: () => onSelect(p),
              ))
          .toList(),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(plan.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        if (isBestValue) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('subscription.bestValue'.tr(),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimaryContainer)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${plan.days} ${plan.days == 1 ? 'day' : 'days'}',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
              else
                Text(plan.amount.formatted,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final benefits = [
      'subscription.benefitCoach'.tr(),
      'subscription.benefitHistory'.tr(),
      'subscription.benefitInsights'.tr(),
      'subscription.benefitCapture'.tr(),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: benefits
            .map((b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(b)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
