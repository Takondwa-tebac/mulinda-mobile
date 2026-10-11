import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';
import 'plan_forms.dart';

/// Shared body: pull-to-refresh + loading/error/empty.
Widget _body<T>({
  required AsyncValue<List<T>> async,
  required VoidCallback onRetry,
  required Future<void> Function() onRefresh,
  required Widget Function(T) tile,
}) {
  return RefreshIndicator(
    onRefresh: onRefresh,
    child: async.when(
      loading: () => const _Fill(child: CircularProgressIndicator()),
      error: (_, _) => _Fill(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('plan.loadError'.tr()),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: Text('plan.retry'.tr())),
          ],
        ),
      ),
      data: (list) => list.isEmpty
          ? _Fill(child: Text('plan.empty'.tr()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: list.map(tile).toList(),
            ),
    ),
  );
}

Widget _fab(BuildContext context, String route) => FloatingActionButton(
      onPressed: () => context.push(route),
      child: const Icon(Icons.add),
    );

Future<bool> _confirmDelete(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('form.confirmDeleteTitle'.tr()),
      content: Text('form.confirmDeleteBody'.tr()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('form.cancel'.tr())),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('form.delete'.tr())),
      ],
    ),
  );
  return ok ?? false;
}

Future<void> _delete(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() del,
  ProviderOrFamily provider,
) async {
  final confirmed = await _confirmDelete(context);
  if (!confirmed || !context.mounted) return;

  try {
    await del();
    ref.invalidate(provider);
    ref.invalidate(dashboardProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('form.deleted'.tr())));
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }
}

class GoalsListScreen extends ConsumerWidget {
  const GoalsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('plan.goals'.tr())),
      floatingActionButton: _fab(context, Routes.goalForm),
      body: _body<GoalItem>(
        async: ref.watch(goalsProvider),
        onRetry: () => ref.invalidate(goalsProvider),
        onRefresh: () async {
          ref.invalidate(goalsProvider);
          await ref.read(goalsProvider.future);
        },
        tile: (g) => _PlanTile(
          title: g.name,
          pending: g.pending,
          value: '${g.current.formatted} / ${g.target.formatted}',
          progress: g.progress,
          onTap: () => context.push(Routes.goalDetail, extra: g),
          onEdit: () => context.push(Routes.goalForm, extra: g),
          onDelete: () => _delete(context, ref, () => ref.read(planRepositoryProvider).deleteGoal(g.id), goalsProvider),
          extra: ('form.contribute'.tr(), () => showContributeSheet(context, ref, g.id)),
        ),
      ),
    );
  }
}

class BudgetsListScreen extends ConsumerWidget {
  const BudgetsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('plan.budgets'.tr())),
      floatingActionButton: _fab(context, Routes.budgetForm),
      body: _body<BudgetItem>(
        async: ref.watch(budgetsProvider),
        onRetry: () => ref.invalidate(budgetsProvider),
        onRefresh: () async {
          ref.invalidate(budgetsProvider);
          await ref.read(budgetsProvider.future);
        },
        tile: (b) => _BudgetCard(
          budget: b,
          onTap: () => context.push(Routes.budgetDetail, extra: b),
          onEdit: () => context.push(Routes.budgetForm, extra: b),
          onDelete: () => _delete(context, ref, () => ref.read(planRepositoryProvider).deleteBudget(b.id), budgetsProvider),
        ),
      ),
    );
  }
}

class LoansListScreen extends ConsumerWidget {
  const LoansListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('plan.loans'.tr())),
      floatingActionButton: _fab(context, Routes.loanForm),
      body: _body<LoanItem>(
        async: ref.watch(loansProvider),
        onRetry: () => ref.invalidate(loansProvider),
        onRefresh: () async {
          ref.invalidate(loansProvider);
          await ref.read(loansProvider.future);
        },
        tile: (l) => _PlanTile(
          title: l.name,
          pending: l.pending,
          value: l.outstanding.formatted,
          sub: 'form.loanStatus.${l.status}'.tr(),
          onTap: () => context.push(Routes.loanDetail, extra: l),
          onEdit: () => context.push(Routes.loanForm, extra: l),
          onDelete: () => _delete(context, ref, () => ref.read(planRepositoryProvider).deleteLoan(l.id), loansProvider),
          extra: ('form.repay'.tr(), () => showRepaySheet(context, ref, l.id)),
        ),
      ),
    );
  }
}

class InvestmentsListScreen extends ConsumerWidget {
  const InvestmentsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('plan.investments'.tr())),
      floatingActionButton: _fab(context, Routes.investmentForm),
      body: _body<InvestmentItem>(
        async: ref.watch(investmentsListProvider),
        onRetry: () => ref.invalidate(investmentsListProvider),
        onRefresh: () async {
          ref.invalidate(investmentsListProvider);
          await ref.read(investmentsListProvider.future);
        },
        tile: (i) => _PlanTile(
          title: i.name,
          pending: i.pending,
          value: i.value.formatted,
          // Term investments show the interest earned so far (estimated by the
          // API from the rate and elapsed days); others show the plain gain.
          sub: '${'invest.type.${i.type}'.tr()} · '
              '${(i.isEstimated ? 'invest.interestSoFar' : 'invest.gain').tr()}: ${i.gain.formatted}',
          subColor: i.gain.isNegative ? Colors.red : null,
          onTap: () => context.push(Routes.investmentDetail, extra: i),
          onEdit: () => context.push(Routes.investmentForm, extra: i),
          onDelete: () => _delete(context, ref, () => ref.read(planRepositoryProvider).deleteInvestment(i.id), investmentsListProvider),
        ),
      ),
    );
  }
}

class ProjectsListScreen extends ConsumerWidget {
  const ProjectsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('plan.projects'.tr())),
      floatingActionButton: _fab(context, Routes.projectForm),
      body: _body<ProjectItem>(
        async: ref.watch(projectsProvider),
        onRetry: () => ref.invalidate(projectsProvider),
        onRefresh: () async {
          ref.invalidate(projectsProvider);
          await ref.read(projectsProvider.future);
        },
        tile: (p) => _PlanTile(
          title: p.name,
          pending: p.pending,
          value: p.spent.formatted,
          valueLabel: 'project.spent'.tr(),
          sub: p.budget?.formatted,
          subLabel: 'project.budget'.tr(),
          progress: p.completionPercentage,
          onTap: () => context.push(Routes.projectDetail, extra: p),
          onEdit: () => context.push(Routes.projectForm, extra: p),
          onDelete: () => _delete(context, ref, () => ref.read(planRepositoryProvider).deleteProject(p.id), projectsProvider),
        ),
      ),
    );
  }
}

/// A budget on the list: the name wraps instead of being squeezed, the figures sit
/// on their own lines, and the state (on track, close, over) is a clear chip.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget, required this.onTap, required this.onEdit, required this.onDelete});

  final BudgetItem budget;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = budget;
    final percent = b.percentage.clamp(0, 999).toDouble();
    final alerting = !b.isExceeded && b.alertThreshold > 0 && b.percentage / 100 >= b.alertThreshold;
    final color = b.isExceeded
        ? scheme.error
        : alerting
            ? const Color(0xFFB26A00)
            : scheme.primary;
    final state = b.isExceeded
        ? 'budgetSpend.overBudget'.tr()
        : alerting
            ? 'budgetSpend.almostThere'.tr()
            : 'budgetSpend.onTrack'.tr();
    final left = b.limit.minorUnits - b.spent.minorUnits;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.pie_chart_outline, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name.isEmpty ? 'budgetSpend.budget'.tr() : b.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.2),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(state,
                                  style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ),
                            Text(
                              b.period == 'weekly' ? 'form.weekly'.tr() : 'form.monthly_period'.tr(),
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                            if (b.pending)
                              Icon(Icons.cloud_upload_outlined, size: 14, color: scheme.tertiary),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (action) {
                      if (action == 'edit') onEdit();
                      if (action == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'edit', child: Text('form.edit'.tr())),
                      PopupMenuItem(value: 'delete', child: Text('form.delete'.tr())),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (percent / 100).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHigh,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _BudgetFigure(label: 'detail.spent'.tr(), value: b.spent.formatted, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BudgetFigure(
                            label: 'detail.limit'.tr(),
                            value: b.limit.formatted,
                            color: scheme.onSurface,
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      b.isExceeded
                          ? 'budgetSpend.overBy'.tr(args: [_overBy(b, -left)])
                          : 'budgetSpend.percentUsed'.tr(args: [percent.toStringAsFixed(0)]),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "MK 12,500" style text for an amount in minor units, borrowing the format of the limit.
  static String _overBy(BudgetItem b, int minor) {
    final amount = (minor / 100).toStringAsFixed(minor % 100 == 0 ? 0 : 2);
    final withCommas = amount.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    final symbol = b.limit.formatted.replaceAll(RegExp(r'[\d,. ]'), '').trim();
    return '$symbol $withCommas';
  }
}

class _BudgetFigure extends StatelessWidget {
  const _BudgetFigure({required this.label, required this.value, required this.color, this.alignEnd = false});

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.title,
    required this.value,
    this.valueLabel,
    this.sub,
    this.subLabel,
    this.subColor,
    this.progress,
    this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.extra,
    this.pending = false,
  });

  final String title;
  final String value;
  final String? valueLabel;
  final String? sub;
  final String? subLabel;
  final Color? subColor;
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final (String, VoidCallback)? extra;

  /// Made offline and not synced yet.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clampedProgress = progress?.clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap ?? onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        if (pending)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Tooltip(
                                message: 'Waiting to sync',
                                child: Icon(Icons.cloud_upload_outlined, size: 16, color: scheme.tertiary),
                              ),
                            ),
                          ),
                        TextSpan(text: title),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      if (valueLabel != null)
                        Text(
                          valueLabel!,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (action) {
                      if (action == 'extra' && extra != null) extra!.$2();
                      if (action == 'edit') onEdit();
                      if (action == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      if (extra != null)
                        PopupMenuItem(
                          value: 'extra',
                          child: Text(extra!.$1),
                        ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('form.edit'.tr()),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('form.delete'.tr()),
                      ),
                    ],
                  ),
                ],
              ),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      if (subLabel != null)
                        Text(
                          '$subLabel: ',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      Text(
                        sub!,
                        style: TextStyle(
                          color: subColor ?? scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              if (clampedProgress != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: clampedProgress,
                            minHeight: 8,
                            backgroundColor: scheme.surfaceContainerHigh,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(clampedProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(child: Padding(padding: const EdgeInsets.all(24), child: child)),
          ),
        ],
      );
}