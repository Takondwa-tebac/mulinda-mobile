import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/dashed_outline.dart';
import '../data/plan_tools_gate.dart';

/// "5 December".
String _dayMonth(DateTime d) => '${d.day} ${'common.monthLong.${d.month}'.tr()}';

/// On Plan in the first two weeks, in place of loans, investments and
/// projects: when they arrive, and a way to show them now.
class MoreToolsBox extends ConsumerWidget {
  const MoreToolsBox({super.key, required this.unlockDay});

  final DateTime? unlockDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final day = unlockDay;
    return DashedOutline(
      key: const ValueKey('plan-more-tools'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day == null ? 'planTools.moreSoon'.tr() : 'planTools.moreFrom'.tr(args: [_dayMonth(day)]),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'planTools.lockedBody'.tr(),
            style: TextStyle(fontSize: 14, height: 1.45, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            key: const ValueKey('plan-show-tools-now'),
            style: TextButton.styleFrom(
              minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch),
              padding: EdgeInsets.zero,
              foregroundColor: context.semantic.brandInk,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => ref.read(planToolsPrefsProvider.notifier).unlock(),
            child: Text('planTools.showNow'.tr()),
          ),
        ],
      ),
    );
  }
}

/// On Home from day 14: loans, investments and projects are now on Plan.
/// Shown once; either button puts it away for good.
class MoreOnPlanCard extends ConsumerWidget {
  const MoreOnPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onPrimaryContainer;
    void dismiss() => ref.read(planToolsPrefsProvider.notifier).dismissMoreOnPlan();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Card(
        key: const ValueKey('home-more-on-plan'),
        margin: EdgeInsets.zero,
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'planTools.moreTitle'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: on),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('planTools.moreBody'.tr(), style: TextStyle(fontSize: 14, height: 1.45, color: on)),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  FilledButton(
                    key: const ValueKey('home-more-on-plan-open'),
                    style: FilledButton.styleFrom(minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch)),
                    onPressed: () {
                      dismiss();
                      context.go(Routes.plan);
                    },
                    child: Text('planTools.openPlan'.tr()),
                  ),
                  TextButton(
                    key: const ValueKey('home-more-on-plan-later'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch),
                      foregroundColor: on,
                    ),
                    onPressed: dismiss,
                    child: Text('planTools.notNow'.tr()),
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
