import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money_json.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/budget_pace.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/plan_models.dart';
import '../widgets/mse_logo.dart';
import '../data/plan_repository.dart';
import 'plan_forms.dart';

/// Shared body: pull-to-refresh + loading/error/empty, an empty-state call to
/// action and a trailing "+ Add …" row after the items.
Widget _body<T>({
  required AsyncValue<List<T>> async,
  required VoidCallback onRetry,
  required Future<void> Function() onRefresh,
  required Widget Function(T) tile,
  required String addLabel,
  required String emptyTitle,
  required VoidCallback onAdd,
}) {
  return RefreshIndicator(
    onRefresh: onRefresh,
    child: async.when(
      loading: () => const SkeletonList(count: 5),
      error: (_, _) => ScrollFill(
        child: ErrorRetry(message: 'plan.loadError'.tr(), onRetry: onRetry),
      ),
      data: (list) => list.isEmpty
          ? ScrollFill(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: emptyTitle,
                body: 'plan.empty'.tr(),
                actionLabel: addLabel,
                onAction: onAdd,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                ...list.map(tile),
                _AddRow(label: addLabel, onTap: onAdd),
              ],
            ),
    ),
  );
}

/// A list screen's app bar with its "+" action.
PreferredSizeWidget _listAppBar(BuildContext context, String title, String addLabel, String route) => AppBar(
  title: Text(title),
  actions: [
    IconButton(
      key: const ValueKey('plan-list-add'),
      tooltip: addLabel,
      icon: const Icon(Icons.add),
      onPressed: () => context.push(route),
    ),
  ],
);

/// "+ Add budget" at the end of a list.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('plan-list-add-row'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.add, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
      appBar: _listAppBar(context, 'plan.goals'.tr(), 'plan2.addGoal'.tr(), Routes.goalForm),
      body: _body<GoalItem>(
        addLabel: 'plan2.addGoal'.tr(),
        emptyTitle: 'plan2.empty.goals'.tr(),
        onAdd: () => context.push(Routes.goalForm),
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
      appBar: _listAppBar(context, 'plan.budgets'.tr(), 'plan2.addBudget'.tr(), Routes.budgetForm),
      body: _body<BudgetItem>(
        addLabel: 'plan2.addBudget'.tr(),
        emptyTitle: 'plan2.empty.budgets'.tr(),
        onAdd: () => context.push(Routes.budgetForm),
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
          onDelete: () =>
              _delete(context, ref, () => ref.read(planRepositoryProvider).deleteBudget(b.id), budgetsProvider),
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
      appBar: _listAppBar(context, 'plan.loans'.tr(), 'plan2.addLoan'.tr(), Routes.loanForm),
      body: _body<LoanItem>(
        addLabel: 'plan2.addLoan'.tr(),
        emptyTitle: 'plan2.empty.loans'.tr(),
        onAdd: () => context.push(Routes.loanForm),
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

/// " · ▲ 2.5% today" for a share whose price moved since the last one entered.
String _todayMove(InvestmentItem i) {
  final trade = i.lastTrade;
  if (trade == null || !trade.hasChange || trade.changePercent == null) return '';
  final arrow = trade.isUp ? '▲' : (trade.isDown ? '▼' : '');
  final pct = (trade.changePercent!.abs() * 100).toStringAsFixed(1);
  return ' · $arrow $pct%';
}

class InvestmentsListScreen extends ConsumerWidget {
  const InvestmentsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _listAppBar(context, 'plan.investments'.tr(), 'plan2.addInvestment'.tr(), Routes.investmentForm),
      body: _body<InvestmentItem>(
        addLabel: 'plan2.addInvestment'.tr(),
        emptyTitle: 'plan2.empty.investments'.tr(),
        onAdd: () => context.push(Routes.investmentForm),
        async: ref.watch(investmentsListProvider),
        onRetry: () => ref.invalidate(investmentsListProvider),
        onRefresh: () async {
          ref.invalidate(investmentsListProvider);
          await ref.read(investmentsListProvider.future);
        },
        tile: (i) => _PlanTile(
          title: i.name,
          leading: i.type == 'shares' ? MseLogo(ticker: i.ticker, name: i.name, size: 36) : null,
          pending: i.pending,
          value: i.value.formatted,
          // Term investments show the interest earned so far (estimated by the
          // API from the rate and elapsed days); others show the plain gain.
          sub:
              '${'invest.type.${i.type}'.tr()} · '
              '${(i.isEstimated ? 'invest.interestSoFar' : 'invest.gain').tr()}: ${i.gain.formatted}'
              '${_todayMove(i)}',
          subColor: i.gain.isNegative ? context.semantic.danger : null,
          onTap: () => context.push(Routes.investmentDetail, extra: i),
          onEdit: () => context.push(Routes.investmentForm, extra: i),
          onDelete: () => _delete(
            context,
            ref,
            () => ref.read(planRepositoryProvider).deleteInvestment(i.id),
            investmentsListProvider,
          ),
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
      appBar: _listAppBar(context, 'plan.projects'.tr(), 'plan2.addProject'.tr(), Routes.projectForm),
      body: _body<ProjectItem>(
        addLabel: 'plan2.addProject'.tr(),
        emptyTitle: 'plan2.empty.projects'.tr(),
        onAdd: () => context.push(Routes.projectForm),
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
          onDelete: () =>
              _delete(context, ref, () => ref.read(planRepositoryProvider).deleteProject(p.id), projectsProvider),
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
    final pace = budgetPace(
      spentMinor: b.spent.minorUnits,
      limitMinor: b.limit.minorUnits,
      from: b.periodFrom,
      to: b.periodTo,
      alertThreshold: b.alertThreshold,
    );
    final health = b.isExceeded ? BudgetHealth.over : pace.health;
    final color = switch (health) {
      BudgetHealth.over => context.semantic.danger,
      BudgetHealth.atRisk => context.semantic.warning,
      BudgetHealth.onTrack => context.semantic.brandInk,
    };
    final state = switch (health) {
      BudgetHealth.over => 'budgetSpend.overBudget'.tr(),
      BudgetHealth.atRisk => 'plan2.status.atRisk'.tr(),
      BudgetHealth.onTrack => 'budgetSpend.onTrack'.tr(),
    };
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
                            StatusChip(
                              label: state,
                              tone: switch (health) {
                                BudgetHealth.over => StatusTone.danger,
                                BudgetHealth.atRisk => StatusTone.warning,
                                BudgetHealth.onTrack => StatusTone.success,
                              },
                            ),
                            Text(
                              b.period == 'weekly' ? 'form.weekly'.tr() : 'form.monthly_period'.tr(),
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                            if (b.pending) Icon(Icons.cloud_upload_outlined, size: 14, color: scheme.tertiary),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'common.more'.tr(),
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
                    ProgressBar(value: percent / 100, health: health, semanticsLabel: b.name),
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
                          ? 'budgetSpend.overBy'.tr(args: [formatMoney(-left / 100, b.limit.currency)])
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
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
          ),
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
    this.leading,
  });

  /// Shown before the title (a company logo).
  final Widget? leading;

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
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (pending)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Tooltip(
                                  message: 'activity2.waitingToSync'.tr(),
                                  child: Icon(Icons.cloud_upload_outlined, size: 16, color: scheme.tertiary),
                                ),
                              ),
                            ),
                          TextSpan(text: title),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The amount shrinks to fit instead of squeezing a long name, and never
                  // takes more than its share of the row.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            value,
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                          ),
                          if (valueLabel != null)
                            Text(valueLabel!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'common.more'.tr(),
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (action) {
                      if (action == 'extra' && extra != null) extra!.$2();
                      if (action == 'edit') onEdit();
                      if (action == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      if (extra != null) PopupMenuItem(value: 'extra', child: Text(extra!.$1)),
                      PopupMenuItem(value: 'edit', child: Text('form.edit'.tr())),
                      PopupMenuItem(value: 'delete', child: Text('form.delete'.tr())),
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
                        Text('$subLabel: ', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                      // Wraps onto a second line (then ends in "...") instead of running off the card.
                      Expanded(
                        child: Text(
                          sub!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subColor ?? scheme.onSurfaceVariant, fontSize: 13),
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
                        child: ProgressBar(value: clampedProgress, semanticsLabel: title),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(clampedProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
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
