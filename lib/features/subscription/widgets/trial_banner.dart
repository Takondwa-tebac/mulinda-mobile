import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_controller.dart';
import '../data/subscription_models.dart';
import 'paywall_sheet.dart';

/// "Free trial: about N hours left" — shown only while the registration trial is
/// running (hidden otherwise). States the real time left; no countdown timer or
/// pressure. Tapping shows what stays free and what the passes cost.
class TrialBanner extends ConsumerWidget {
  const TrialBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub =
        ref.watch(currentUserProvider)?.subscription ??
        const SubscriptionInfo.none();
    final hours = trialHoursLeft(sub, DateTime.now());
    if (hours == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('trial-banner'),
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showPaywall(context, surface: 'trial_banner'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.hourglass_bottom_rounded,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'subscription.trialBanner.title'.tr(
                        namedArgs: {'hours': '$hours'},
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'subscription.trialBanner.body'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
