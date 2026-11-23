import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/home_alert_dismissals.dart';
import '../data/subscription_models.dart';
import 'paywall_sheet.dart';

/// "Free trial: N days (or about N hours) left", shown only while the trial is
/// running (hidden otherwise). States the real time left; no countdown timer or
/// pressure. Tapping shows what stays free and what the passes cost.
///
/// The close button puts it away for this trial; closed with more than two
/// days left, it comes back once for the last 48 hours.
class TrialBanner extends ConsumerWidget {
  const TrialBanner({super.key, this.margin = EdgeInsets.zero});

  /// Space around the banner, applied only while it is visible.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub =
        ref.watch(currentUserProvider)?.subscription ??
        const SubscriptionInfo.none();
    final hours = trialHoursLeft(sub, DateTime.now());
    if (hours == null) return const SizedBox.shrink();
    final key = alertKeyFor(ref, sub, trialBannerDismissedKey);
    final dismissal = key == null ? AlertDismissal.none : ref.watch(alertDismissalProvider(key));
    // Hidden until the stored choice is known, so it never flashes away.
    if (dismissal == null || !trialBannerVisible(hoursLeft: hours, dismissal: dismissal)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final banner = Material(
      key: const ValueKey('trial-banner'),
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showPaywall(context, surface: 'trial_banner'),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 0, 4),
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
                      // Days for a longer trial, hours near the end.
                      hours > 48
                          ? 'subscription.trialBanner.titleDays'.tr(
                              namedArgs: {'days': '${(hours / 24).ceil()}'},
                            )
                          : 'subscription.trialBanner.title'.tr(
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
              IconButton(
                key: const ValueKey('trial-banner-close'),
                tooltip: 'subscription.trialBanner.close'.tr(),
                constraints: const BoxConstraints(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch),
                color: scheme.onSecondaryContainer,
                icon: const Icon(Icons.close_rounded),
                onPressed: key == null
                    ? null
                    : () => ref.read(alertDismissalProvider(key).notifier).set(trialDismissalFor(hours, dismissal)),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(padding: margin, child: banner);
  }
}
