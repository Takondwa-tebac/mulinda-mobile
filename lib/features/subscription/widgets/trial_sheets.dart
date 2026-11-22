import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../paywall_prompt.dart';

/// "Premium is on for N days": shown once, right after a premium tap started
/// the free trial, before the person carries on into the feature.
Future<void> showTrialStartedSheet(BuildContext context, {int? days}) {
  return showAppSheetWith<void>(
    context,
    builder: (sheet) {
      final scheme = Theme.of(sheet).colorScheme;
      final text = Theme.of(sheet).textTheme;
      return AppSheet(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.check_rounded, size: 30, color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              days == null
                  ? 'upgrade.trial.startedNoDays'.tr()
                  : 'upgrade.trial.started'.tr(namedArgs: {'days': '$days'}),
              key: const ValueKey('trial-started-title'),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'upgrade.trial.startedBody'.tr(),
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
        footer: FilledButton(
          key: const ValueKey('trial-started-continue'),
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text('upgrade.trial.continue'.tr()),
        ),
      );
    },
  );
}

/// What the person chose on the trial offer.
enum TrialOfferChoice { start, pricing }

/// Offer the free trial without starting it. Used when the app, not a tap,
/// ran into a premium wall (a 402 while loading), so nothing starts unasked.
Future<TrialOfferChoice?> showTrialOfferSheet(BuildContext context, {int? days, String? entitlement}) {
  return showAppSheetWith<TrialOfferChoice>(
    context,
    builder: (sheet) {
      final scheme = Theme.of(sheet).colorScheme;
      final text = Theme.of(sheet).textTheme;
      return AppSheet(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              days == null
                  ? 'upgrade.trial.offerNoDays'.tr()
                  : 'upgrade.trial.offer'.tr(namedArgs: {'days': '$days'}),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              paywallHeadlineKey(entitlement).tr(),
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'upgrade.trial.offerBody'.tr(),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const ValueKey('trial-offer-start'),
              style: BottomActionBar.ctaButtonStyle(sheet),
              onPressed: () => Navigator.of(sheet).pop(TrialOfferChoice.start),
              child: Text('upgrade.trial.start'.tr()),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.of(sheet).pop(TrialOfferChoice.pricing),
              child: Text('paywall.seePlans'.tr()),
            ),
          ],
        ),
      );
    },
  );
}
