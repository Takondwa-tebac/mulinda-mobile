import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/app_date_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/admin_repository.dart';
import '../data/funnel_models.dart';

typedef FunnelQuery = ({DateTime from, DateTime to, bool newUsersOnly});

final funnelProvider = FutureProvider.autoDispose.family<FunnelReport, FunnelQuery>(
  (ref, q) => ref.read(adminRepositoryProvider).funnel(from: q.from, to: q.to, newUsersOnly: q.newUsersOnly),
);

/// The product funnel for a date range: each step with its users, a bar
/// relative to the first step and the conversion from the step before, the
/// trial → paid summary, and the side events (payments failed, paywall…).
class FunnelSection extends ConsumerStatefulWidget {
  const FunnelSection({super.key, this.initialDays = 30});

  final int initialDays;

  @override
  ConsumerState<FunnelSection> createState() => _FunnelSectionState();
}

class _FunnelSectionState extends ConsumerState<FunnelSection> {
  late DateTime _to = DateUtils.dateOnly(DateTime.now());
  late DateTime _from = _to.subtract(Duration(days: widget.initialDays - 1));
  bool _newUsersOnly = true;

  FunnelQuery get _query => (from: _from, to: _to, newUsersOnly: _newUsersOnly);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(funnelProvider(_query));
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppDateField(
                    label: 'common.from'.tr(),
                    value: _from,
                    lastDate: _to,
                    onChanged: (d) => setState(() => _from = d ?? _from),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppDateField(
                    label: 'common.to'.tr(),
                    value: _to,
                    firstDate: _from,
                    lastDate: DateTime.now(),
                    onChanged: (d) => setState(() => _to = d ?? _to),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _newUsersOnly,
              onChanged: (v) => setState(() => _newUsersOnly = v),
              title: Text('admin2.funnel.newUsersOnly'.tr()),
              subtitle: Text('admin2.funnel.newUsersOnlySub'.tr()),
            ),
            const SizedBox(height: AppSpacing.sm),
            async.when(
              loading: () => Shimmer(
                child: Column(
                  children: [
                    for (var i = 0; i < 5; i++)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: SkeletonBox(height: 34)),
                  ],
                ),
              ),
              error: (_, _) => ErrorRetry(
                compact: true,
                message: 'admin2.funnel.loadError'.tr(),
                onRetry: () => ref.invalidate(funnelProvider(_query)),
              ),
              data: (report) => report.isEmpty
                  ? EmptyState(
                      compact: true,
                      icon: Icons.filter_alt_off_outlined,
                      title: 'admin2.funnel.emptyTitle'.tr(),
                      body: 'admin2.funnel.emptyBody'.tr(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final step in report.steps) FunnelStepRow(step: step, top: report.top),
                        const SizedBox(height: AppSpacing.md),
                        _TrialToPaid(report: report),
                        if (report.secondary.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'admin2.funnel.secondary'.tr(),
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                          ),
                          for (final s in report.secondary)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(funnelStepLabel(s.name)),
                              trailing: Text(
                                'admin2.funnel.usersEvents'.tr(args: ['${s.users}', '${s.events}']),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A readable name for a funnel event, with the raw name as the fallback.
String funnelStepLabel(String name) {
  final key = 'admin2.funnel.step.$name';
  final label = key.tr();
  return label == key ? name.replaceAll('_', ' ') : label;
}

/// One funnel step: name, users, a bar relative to the top step and the
/// conversion from the previous step.
class FunnelStepRow extends StatelessWidget {
  const FunnelStepRow({super.key, required this.step, required this.top});

  final FunnelStep step;
  final int top;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = top == 0 ? 0.0 : step.users / top;
    final conversion = step.conversion;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  funnelStepLabel(step.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text('${step.users}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (conversion != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${(conversion * 100).toStringAsFixed(conversion < 0.1 ? 1 : 0)}%',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: scheme.surfaceContainerHigh,
              color: scheme.primary,
              semanticsLabel: funnelStepLabel(step.name),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrialToPaid extends StatelessWidget {
  const _TrialToPaid({required this.report});

  final FunnelReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    final rate = report.trialToPaid;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: s.successContainer, borderRadius: AppRadius.card),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, color: s.success),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'admin2.funnel.trialToPaid'.tr(
                args: [
                  '${report.paidUsers}',
                  '${report.trialUsers}',
                  rate == null ? '–' : '${(rate * 100).toStringAsFixed(1)}%',
                ],
              ),
              style: TextStyle(color: s.success, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
