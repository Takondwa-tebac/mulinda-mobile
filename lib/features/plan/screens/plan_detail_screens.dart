import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import '../../activity/screens/add_transaction_screen.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';
import 'plan_forms.dart';

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

Future<void> _deleteAndPop(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() del,
  ProviderOrFamily provider,
) async {
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
  if (ok != true || !context.mounted) return;
  try {
    await del();
    ref.invalidate(provider);
    ref.invalidate(dashboardProvider);
    if (context.mounted) context.pop();
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({required this.onEdit, required this.onDelete});
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'form.edit'.tr(), onPressed: onEdit),
      IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'form.delete'.tr(), onPressed: onDelete),
    ]);
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double progress;
  final String leftLabel, leftValue, rightLabel, rightValue;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = danger ? scheme.error : scheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(icon, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                Text('${(progress * 100).toStringAsFixed(0)}%',
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 12,
                backgroundColor: scheme.surfaceContainerHigh,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _AmountCol(label: leftLabel, value: leftValue, color: color),
                _AmountCol(
                    label: rightLabel,
                    value: rightValue,
                    color: scheme.onSurfaceVariant,
                    align: CrossAxisAlignment.end),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountCol extends StatelessWidget {
  const _AmountCol({
    required this.label,
    required this.value,
    required this.color,
    this.align = CrossAxisAlignment.start,
  });
  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 15)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      title: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

class BudgetDetailScreen extends ConsumerWidget {
  const BudgetDetailScreen({super.key, required this.budget});
  final BudgetItem budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stay live after edits.
    final b = ref.watch(budgetsProvider).maybeWhen(
          data: (list) => list.firstWhere((e) => e.id == budget.id, orElse: () => budget),
          orElse: () => budget,
        );

    final remaining = b.limit.minorUnits - b.spent.minorUnits;
    final remainingMajor = (remaining / 100).toStringAsFixed(2);
    final currency = b.limit.formatted.replaceAll(RegExp(r'[\d,. ]'), '').trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(b.name.isEmpty ? 'plan.budgets'.tr() : b.name, overflow: TextOverflow.ellipsis),
        actions: [
          _DetailActions(
            onEdit: () => context.push(Routes.budgetForm, extra: b),
            onDelete: () => _deleteAndPop(
                context, ref, () => ref.read(planRepositoryProvider).deleteBudget(b.id), budgetsProvider),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _ProgressCard(
            icon: Icons.pie_chart_outline,
            title: b.name.isEmpty ? 'plan.budgets'.tr() : b.name,
            subtitle: 'form.${b.period == 'weekly' ? 'weekly' : 'monthly_period'}'.tr(),
            progress: (b.percentage / 100).clamp(0, 1).toDouble(),
            danger: b.isExceeded,
            leftLabel: 'detail.spent'.tr(),
            leftValue: b.spent.formatted,
            rightLabel: 'detail.limit'.tr(),
            rightValue: b.limit.formatted,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'detail.remaining'.tr(),
                  value: b.isExceeded ? 'detail.overBudget'.tr() : '$currency $remainingMajor',
                ),
                _InfoRow(
                  icon: Icons.notifications_outlined,
                  label: 'detail.alertAt'.tr(),
                  value: '${(b.alertThreshold * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loan
// ---------------------------------------------------------------------------

class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.loan});
  final LoanItem loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(loansProvider).maybeWhen(
          data: (list) => list.firstWhere((e) => e.id == loan.id, orElse: () => loan),
          orElse: () => loan,
        );

    final principalMinor = l.principal.minorUnits;
    final paidMinor = (principalMinor - l.outstanding.minorUnits).clamp(0, principalMinor);
    final progress = principalMinor > 0 ? paidMinor / principalMinor : 0.0;
    final isClosed = l.status != 'active';

    return Scaffold(
      appBar: AppBar(
        title: Text(l.name, overflow: TextOverflow.ellipsis),
        actions: [
          _DetailActions(
            onEdit: () => context.push(Routes.loanForm, extra: l),
            onDelete: () => _deleteAndPop(
                context, ref, () => ref.read(planRepositoryProvider).deleteLoan(l.id), loansProvider),
          ),
        ],
      ),
      floatingActionButton: isClosed
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showRepaySheet(context, ref, l.id),
              icon: const Icon(Icons.payments_outlined),
              label: Text('form.repay'.tr()),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _ProgressCard(
            icon: Icons.account_balance_outlined,
            title: l.name,
            subtitle: 'form.loanStatus.${l.status}'.tr(),
            progress: progress.toDouble(),
            leftLabel: 'detail.outstanding'.tr(),
            leftValue: l.outstanding.formatted,
            rightLabel: 'detail.principal'.tr(),
            rightValue: l.principal.formatted,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                if (l.lender != null && l.lender!.isNotEmpty)
                  _InfoRow(icon: Icons.store_outlined, label: 'form.lender'.tr(), value: l.lender!),
                _InfoRow(
                  icon: Icons.percent,
                  label: 'form.interestRate'.tr(),
                  value: '${(l.annualInterestRate * 100).toStringAsFixed(1)}%',
                ),
                _InfoRow(
                  icon: Icons.tune,
                  label: 'form.interestType'.tr(),
                  value: 'form.interestTypes.${l.interestType}'.tr(),
                ),
                _InfoRow(
                  icon: Icons.calendar_month_outlined,
                  label: 'form.termMonths'.tr(),
                  value: '${l.termMonths}',
                ),
                if (l.disbursedAt != null)
                  _InfoRow(icon: Icons.event_outlined, label: 'form.disbursedAt'.tr(), value: l.disbursedAt!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Project
// ---------------------------------------------------------------------------

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.project});
  final ProjectItem project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(projectsProvider).maybeWhen(
          data: (list) => list.firstWhere((e) => e.id == project.id, orElse: () => project),
          orElse: () => project,
        );

    final txns = ref.watch(transactionsProvider);
    final budgetMinor = p.budget?.minorUnits ?? 0;
    final progress = budgetMinor > 0 ? (p.spent.minorUnits / budgetMinor).clamp(0, 1).toDouble() : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, overflow: TextOverflow.ellipsis),
        actions: [
          _DetailActions(
            onEdit: () => context.push(Routes.projectForm, extra: p),
            onDelete: () => _deleteAndPop(
                context, ref, () => ref.read(planRepositoryProvider).deleteProject(p.id), projectsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddTransactionScreen(projectId: p.id, projectName: p.name),
            ),
          );
          ref.invalidate(transactionsProvider);
          ref.invalidate(projectsProvider);
        },
        icon: const Icon(Icons.add),
        label: Text('detail.recordSpend'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          if (p.budget != null)
            _ProgressCard(
              icon: Icons.home_work_outlined,
              title: p.name,
              subtitle: 'form.projectStatus.${p.status}'.tr(),
              progress: progress,
              danger: p.spent.minorUnits > budgetMinor && budgetMinor > 0,
              leftLabel: 'detail.spent'.tr(),
              leftValue: p.spent.formatted,
              rightLabel: 'detail.budget'.tr(),
              rightValue: p.budget!.formatted,
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.home_work_outlined),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('form.projectStatus.${p.status}'.tr()),
                trailing: Text(p.spent.formatted,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
              ),
            ),
          if (p.description != null && p.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(p.description!),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('detail.transactions'.tr(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          txns.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Text('activity.loadError'.tr()),
            data: (list) {
              final projectTxns = list.where((t) => t.projectId == p.id).toList();
              if (projectTxns.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('detail.noProjectTxns'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                );
              }
              return Column(children: projectTxns.map((t) => _ProjectTxnTile(txn: t)).toList());
            },
          ),
        ],
      ),
    );
  }
}

class _ProjectTxnTile extends StatelessWidget {
  const _ProjectTxnTile({required this.txn});
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = txn.merchant?.isNotEmpty == true ? txn.merchant! : (txn.categoryName ?? txn.type);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: txn.isIncome ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          foregroundColor: txn.isIncome ? scheme.onPrimaryContainer : scheme.onSurface,
          child: Icon(txn.isIncome ? Icons.south_west : Icons.north_east, size: 18),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(txn.date),
        trailing: Text(
          '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}',
          style: TextStyle(fontWeight: FontWeight.w700, color: txn.isIncome ? scheme.primary : scheme.onSurface),
        ),
      ),
    );
  }
}
