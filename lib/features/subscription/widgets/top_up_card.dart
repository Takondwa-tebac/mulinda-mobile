import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money_json.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../auth/providers/auth_controller.dart';
import '../checkout_flow.dart';
import '../data/home_alert_dismissals.dart';
import '../data/subscription_models.dart';
import '../upgrade_flow.dart';

/// "Make it a week for MK 1,000 more": while a paid Day pass runs, pay only
/// the difference to turn it into a Week. The amount comes from the API.
/// Renders nothing when there is no offer, or once closed for this pass.
class TopUpCard extends ConsumerStatefulWidget {
  const TopUpCard({super.key, this.surface = 'unknown', this.margin = EdgeInsets.zero});

  final String surface;

  /// Space around the card, applied only while it is visible.
  final EdgeInsetsGeometry margin;

  @override
  ConsumerState<TopUpCard> createState() => _TopUpCardState();
}

class _TopUpCardState extends ConsumerState<TopUpCard> {
  bool _busy = false;

  Future<void> _topUp(TopUpOffer offer) async {
    setState(() => _busy = true);
    final outcome = await purchasePass(
      context,
      ref,
      period: offer.period,
      topUp: true,
      surface: widget.surface,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final key = outcome == CheckoutOutcome.paid ? null : unpaidMessageKey(outcome);
    if (key != null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(key.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(currentUserProvider)?.subscription ?? const SubscriptionInfo.none();
    if (!showTopUp(sub)) return const SizedBox.shrink();
    final offer = sub.topUp!;
    final dismissKey = alertKeyFor(ref, sub, topUpCardDismissedKey);
    final dismissal = dismissKey == null ? AlertDismissal.none : ref.watch(alertDismissalProvider(dismissKey));
    if (dismissal != AlertDismissal.none) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final amount = formatMinorShort(offer.amountMinor, offer.currency);

    return Padding(
      padding: widget.margin,
      child: Container(
        key: const ValueKey('top-up-card'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppRadius.card,
          border: Border.all(color: scheme.secondary, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      'upgrade.topUp.title'.tr(namedArgs: {'amount': amount}),
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (dismissKey != null)
                  // Pulled into the card padding so the title keeps its line.
                  Transform.translate(
                    offset: const Offset(AppSpacing.sm, -AppSpacing.sm),
                    child: IconButton(
                      key: const ValueKey('top-up-close'),
                      tooltip: 'upgrade.topUp.close'.tr(),
                      constraints: const BoxConstraints(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch),
                      color: scheme.onSurfaceVariant,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => ref.read(alertDismissalProvider(dismissKey).notifier).set(AlertDismissal.done),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'upgrade.topUp.body'.tr(),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const ValueKey('top-up-pay'),
              style: BottomActionBar.ctaButtonStyle(context),
              onPressed: _busy ? null : () => _topUp(offer),
              child: _busy
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onSecondary),
                    )
                  : Text('upgrade.topUp.cta'.tr(namedArgs: {'amount': amount})),
            ),
          ],
        ),
      ),
    );
  }
}
