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
import 'plan_lists.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goal});

  final GoalItem goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pct = (goal.progress * 100).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'form.edit'.tr(),
            onPressed: () => context.push(Routes.goalForm, extra: goal),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'form.delete'.tr(),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          // Progress ring-style card
          Card(
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
                        child: const Icon(Icons.flag_outlined, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(goal.name,
                                style: text.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              'goal.type.${goal.type}'.tr(
                                  fallbackKey: goal.type),
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Text('$pct%',
                          style: text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: goal.progress,
                      minHeight: 12,
                      backgroundColor: scheme.surfaceContainerHigh,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _AmountCol(
                          label: 'goal.saved'.tr(),
                          value: goal.current.formatted,
                          color: scheme.primary),
                      _AmountCol(
                          label: 'goal.target'.tr(),
                          value: goal.target.formatted,
                          color: scheme.onSurfaceVariant,
                          align: CrossAxisAlignment.end),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Detail rows
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  if (goal.targetDate != null)
                    _InfoRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'goal.targetDate'.tr(),
                      value: goal.targetDate!,
                    ),
                  if (goal.monthlyContribution != null)
                    _InfoRow(
                      icon: Icons.repeat_outlined,
                      label: 'goal.monthly'.tr(),
                      value: goal.monthlyContribution!.formatted,
                    ),
                  _InfoRow(
                    icon: Icons.savings_outlined,
                    label: 'goal.remaining'.tr(),
                    value: (goal.target.minorUnits - goal.current.minorUnits) > 0
                        ? _remaining(goal)
                        : 'goal.complete'.tr(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showContributeSheet(context, ref, goal.id),
        icon: const Icon(Icons.add),
        label: Text('form.contribute'.tr()),
      ),
    );
  }

  String _remaining(GoalItem g) {
    final diff = g.target.minorUnits - g.current.minorUnits;
    final currency = g.target.formatted.replaceAll(RegExp(r'[\d,. ]'), '').trim();
    final major = diff / 100;
    return '$currency ${major.toStringAsFixed(2)}';
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('form.confirmDeleteTitle'.tr()),
        content: Text('form.confirmDeleteBody'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('form.cancel'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('form.delete'.tr())),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(planRepositoryProvider).deleteGoal(goal.id);
      ref.invalidate(goalsProvider);
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
}

class _AmountCol extends StatelessWidget {
  const _AmountCol(
      {required this.label,
      required this.value,
      required this.color,
      this.align = CrossAxisAlignment.start});

  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: color, fontSize: 15)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      title: Text(label,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      trailing: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
