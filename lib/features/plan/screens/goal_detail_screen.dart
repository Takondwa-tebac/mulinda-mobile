import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/data/dashboard_repository.dart' show dashboardProvider;
import '../data/plan_models.dart';
import '../data/plan_repository.dart';
import 'plan_forms.dart' show showContributeSheet, showEditContributionSheet;


class GoalDetailScreen extends ConsumerStatefulWidget {
  const GoalDetailScreen({super.key, required this.goal});

  final GoalItem goal;

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pct = (widget.goal.progress * 100).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.goal.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'form.edit'.tr(),
            onPressed: () => context.push(Routes.goalForm, extra: widget.goal),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'form.delete'.tr(),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
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
                              Text(
                                widget.goal.name,
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'goal.type.${widget.goal.type}'.tr(),
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: widget.goal.progress,
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
                          value: widget.goal.current.formatted,
                          color: scheme.primary,
                        ),
                        _AmountCol(
                          label: 'goal.target'.tr(),
                          value: widget.goal.target.formatted,
                          color: scheme.onSurfaceVariant,
                          align: CrossAxisAlignment.end,
                        ),
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
                    if (widget.goal.targetDate != null)
                      _InfoRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'goal.targetDate'.tr(),
                        value: widget.goal.targetDate!,
                      ),
                    if (widget.goal.monthlyContribution != null)
                      _InfoRow(
                        icon: Icons.repeat_outlined,
                        label: 'goal.monthly'.tr(),
                        value: widget.goal.monthlyContribution!.formatted,
                      ),
                    _InfoRow(
                      icon: Icons.savings_outlined,
                      label: 'goal.remaining'.tr(),
                      value: (widget.goal.target.minorUnits -
                                  widget.goal.current.minorUnits) >
                              0
                          ? _remaining(widget.goal)
                          : 'goal.complete'.tr(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contributions section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'goal.contributions'.tr(),
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => showContributeSheet(
                            context,
                            ref,
                            widget.goal.id,
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('form.add'.tr()),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ContributionsList(goalId: widget.goal.id),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showContributeSheet(context, ref, widget.goal.id),
        icon: const Icon(Icons.add),
        label: Text('form.contribute'.tr()),
      ),
    );
  }

  String _remaining(GoalItem g) {
    final diff = g.target.minorUnits - g.current.minorUnits;
    final currency = g.target.formatted
        .replaceAll(RegExp(r'[\d,. ]'), '')
        .trim();
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
            child: Text('form.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('form.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(planRepositoryProvider).deleteGoal(widget.goal.id);
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

/// One contribution, laid out so long amounts never wrap: the amount takes the
/// flexible space (and scales down if it still does not fit) while the actions
/// collapse into a single overflow menu instead of two fixed-width buttons.
class _ContributionCard extends StatelessWidget {
  const _ContributionCard({
    required this.contribution,
    required this.onEdit,
    required this.onDelete,
  });

  final GoalContribution contribution;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String? get _date {
    final raw = contribution.contributedAt;
    if (raw == null || raw.isEmpty) return null;
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = contribution.note;
    final hasNote = note != null && note.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.savings_outlined, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    contribution.amount.formatted,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                if (_date != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.event_outlined, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _date!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasNote) ...[
                  const SizedBox(height: 4),
                  Text(
                    note.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert, size: 20, color: scheme.onSurfaceVariant),
            onSelected: (action) {
              if (action == 'edit') onEdit();
              if (action == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: 10),
                  Text('form.edit'.tr()),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 10),
                  Text('form.delete'.tr(), style: TextStyle(color: scheme.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContributionsList extends ConsumerWidget {
  const _ContributionsList({required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final contributionsAsync = ref.watch(goalContributionsProvider(goalId));

    return contributionsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('goal.contributionsError'.tr(),
              style: TextStyle(color: scheme.error)),
        ),
      ),
      data: (contributions) {
        if (contributions.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.savings_outlined,
                    size: 48,
                    color: scheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'goal.noContributions'.tr(),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            for (final c in contributions)
              _ContributionCard(
                contribution: c,
                onEdit: () => _editContribution(context, ref, c),
                onDelete: () => _deleteContribution(context, ref, c),
              ),
          ],
        );
      },
    );
  }

  void _editContribution(BuildContext context, WidgetRef ref, GoalContribution contribution) {
    showEditContributionSheet(context, ref, goalId, contribution);
  }

  void _deleteContribution(BuildContext context, WidgetRef ref, GoalContribution contribution) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('form.confirmDeleteTitle'.tr()),
        content: Text('form.confirmDeleteBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('form.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('form.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(planRepositoryProvider).deleteGoalContribution(goalId, contribution.id);
      ref.invalidate(goalContributionsProvider(goalId));
      ref.invalidate(goalsProvider);
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
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      title: Text(
        label,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}