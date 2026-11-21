import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/money/money_json.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../auth/providers/auth_controller.dart';
import '../../capture/data/sms_outbox.dart';
import '../checkout_flow.dart';
import '../data/subscription_models.dart';
import '../data/subscription_repository.dart';
import '../paywall_prompt.dart';
import '../screens/pricing_screen.dart';
import '../upgrade_flow.dart';

/// Messages captured on this phone that are still waiting to be recorded
/// (the server holds them back once the free allowance is used).
final waitingSmsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await SmsOutbox.instance.pendingCount();
  } catch (_) {
    return 0;
  }
});

/// The free SMS allowance is used up: offer a Day pass for the waiting
/// messages, or all passes. Returns true when the person paid.
Future<bool> showLimitReachedSheet(BuildContext context, {String surface = 'unknown'}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => LimitReachedSheet(surface: surface),
  );
  return paid ?? false;
}

class LimitReachedSheet extends ConsumerStatefulWidget {
  const LimitReachedSheet({super.key, this.surface = 'unknown'});

  final String surface;

  @override
  ConsumerState<LimitReachedSheet> createState() => _LimitReachedSheetState();
}

class _LimitReachedSheetState extends ConsumerState<LimitReachedSheet> {
  bool _busy = false;

  Future<void> _buyDay(PlanOption day) async {
    setState(() => _busy = true);
    final outcome = await purchasePass(context, ref, period: day.period, surface: 'limit_sheet');
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == CheckoutOutcome.paid) {
      Navigator.of(context).pop(true);
    } else if (outcome != null) {
      final key = unpaidMessageKey(outcome);
      if (key != null) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(key.tr())));
      }
    }
  }

  Future<void> _seeAll() async {
    final navigator = Navigator.of(context);
    final paid = await openPricing(context, entitlement: smsCaptureEntitlement, surface: 'limit_sheet');
    if (paid && navigator.mounted) navigator.pop(true);
  }

  @override
  void initState() {
    super.initState();
    Analytics.track('limit_sheet_viewed', {'surface': widget.surface});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sub = ref.watch(currentUserProvider)?.subscription ?? const SubscriptionInfo.none();
    final sms = sub.smsCapture;
    final limit = sms != null && sms.limit > 0 ? sms.limit : null;
    final resets = sms?.resetsAt;
    final waiting = ref.watch(waitingSmsCountProvider).valueOrNull ?? 0;
    final plans = ref.watch(plansProvider).valueOrNull ?? const <PlanOption>[];
    final day = dayPassPlan(plans);
    final locale = context.locale.languageCode;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            limit == null
                ? 'upgrade.limit.titleNoCount'.tr()
                : 'upgrade.limit.title'.tr(namedArgs: {'limit': '$limit'}),
            key: const ValueKey('limit-sheet-title'),
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
          ),
          if (waiting > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'upgrade.limit.waiting'.tr(namedArgs: {'count': '$waiting'}),
              key: const ValueKey('limit-sheet-waiting'),
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _Benefit('upgrade.limit.benefitCapture'.tr()),
          const SizedBox(height: AppSpacing.sm),
          _Benefit('upgrade.limit.benefitCoach'.tr()),
          const SizedBox(height: AppSpacing.xl),
          if (day != null) ...[
            FilledButton(
              key: const ValueKey('limit-sheet-day'),
              style: BottomActionBar.ctaButtonStyle(context),
              onPressed: _busy ? null : () => _buyDay(day),
              child: _busy
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onSecondary),
                    )
                  : Text(
                      'upgrade.limit.dayPass'.tr(namedArgs: {
                        'amount': formatMinorShort(day.amount.minorUnits, day.amount.currency),
                      }),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          OutlinedButton(
            key: const ValueKey('limit-sheet-all'),
            onPressed: _busy ? null : _seeAll,
            child: Text('upgrade.limit.seeAll'.tr()),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              resets == null
                  ? 'upgrade.limit.notNow'.tr()
                  : 'upgrade.limit.notNowUntil'.tr(namedArgs: {
                      'date': DateFormat('d MMMM', locale).format(resets),
                    }),
              textAlign: TextAlign.center,
            ),
          ),
          Text(
            'upgrade.limit.stillFree'.tr(),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(Icons.check_rounded, size: 20, color: context.semantic.brandInk)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, height: 1.4))),
      ],
    );
  }
}
