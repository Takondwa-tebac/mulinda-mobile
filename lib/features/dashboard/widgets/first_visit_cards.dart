import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../capture/data/sms_auto_capture.dart';
import '../../onboarding/first_run.dart';

/// The Home greeting. On the first visit there is no "Welcome back": it is
/// "Hi {name}", or just "Hi" while no name is known (signup no longer asks).
String homeGreeting({String? firstName, required bool firstVisit}) {
  final name = firstName?.trim() ?? '';
  if (firstVisit) return name.isEmpty ? 'home.hi'.tr() : 'home.hiName'.tr(args: [name]);
  return name.isEmpty ? 'home.greeting'.tr() : '${'home.greeting'.tr()}, $name';
}

/// "{n} to check": what the import recorded, waiting for the user's look.
class ToCheckCard extends StatelessWidget {
  const ToCheckCard({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Material(
        key: const ValueKey('home-to-check'),
        color: scheme.primaryContainer,
        borderRadius: AppRadius.card,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: () => context.push(Routes.review),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined, color: scheme.onPrimaryContainer),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'home3.toCheck'.tr(args: ['$count']),
                        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'home3.toCheckBody'.tr(),
                        style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether automatic SMS capture is on (for the get-started checklist).
final smsCaptureOnProvider = FutureProvider.autoDispose<bool>((ref) => SmsAutoCapture.isEnabled());

/// "Get started in 3 steps" for a user with nothing captured automatically:
/// capture (or paste on iOS), today's spending, one budget. Done steps tick.
class GetStartedSteps extends ConsumerWidget {
  const GetStartedSteps({super.key, required this.hasTransactions, required this.hasBudget});

  final bool hasTransactions;
  final bool hasBudget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final android = smsStepSupported;
    final captureOn = android && (ref.watch(smsCaptureOnProvider).valueOrNull ?? false);

    Widget step(IconData icon, String title, String body, String route, bool done) => ListTile(
      leading: CircleAvatar(
        backgroundColor: done ? context.semantic.successContainer : scheme.primaryContainer,
        foregroundColor: done ? context.semantic.success : scheme.onPrimaryContainer,
        child: Icon(done ? Icons.check_rounded : icon),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: done ? TextDecoration.lineThrough : null,
          color: done ? scheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(body),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Card(
        key: const ValueKey('home-get-started'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
                child: Text(
                  'home3.stepsTitle'.tr(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (android)
                step(
                  Icons.sms_outlined,
                  'home3.stepCapture'.tr(),
                  'home3.stepCaptureSub'.tr(),
                  Routes.permissions,
                  captureOn,
                )
              else
                step(Icons.content_paste, 'home3.stepPaste'.tr(), 'home3.stepPasteSub'.tr(), Routes.pasteSms, false),
              step(
                Icons.edit_outlined,
                'home3.stepToday'.tr(),
                'home3.stepTodaySub'.tr(),
                Routes.addTransaction,
                hasTransactions,
              ),
              step(Icons.pie_chart_outline, 'home3.stepBudget'.tr(), 'home3.stepBudgetSub'.tr(), Routes.budgetForm, hasBudget),
            ],
          ),
        ),
      ),
    );
  }
}
