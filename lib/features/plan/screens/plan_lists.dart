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
  if (!await _confirmDelete(context)) return;
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
        tile: (b) => _PlanTile(
          title: b.name,
          value: '${b.spent.formatted} / ${b.limit.formatted}',
          progress: (b.percentage / 100).clamp(0, 1).toDouble(),
          danger: b.isExceeded,
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
          value: i.value.formatted,
          sub: i.gain.formatted,
          subColor: i.gain.isNegative ? Colors.red : null,
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
          value: p.spent.formatted,
          sub: p.budget?.formatted,
          onTap: () => context.push(Routes.projectDetail, extra: p),
          onEdit: () => context.push(Routes.projectForm, extra: p),
          onDelete: () => _delete(context, ref, () => ref.read(planRepositoryProvider).deleteProject(p.id), projectsProvider),
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.title,
    required this.value,
    this.sub,
    this.subColor,
    this.progress,
    this.danger = false,
    this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.extra,
  });

  final String title;
  final String value;
  final String? sub;
  final Color? subColor;
  final double? progress;
  final bool danger;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final (String, VoidCallback)? extra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap ?? onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    value,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: danger ? scheme.error : scheme.primary),
                  ),
                ],
              ),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub!,
                      style: TextStyle(
                          color: subColor ?? scheme.onSurfaceVariant,
                          fontSize: 13)),
                ),
              if (progress != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHigh,
                    color: danger ? scheme.error : scheme.primary,
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
