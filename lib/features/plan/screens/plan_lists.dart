import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/plan_models.dart';
import '../data/plan_repository.dart';

/// Shared body for the Plan list screens: pull-to-refresh + loading/error/empty.
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: list.map(tile).toList(),
            ),
    ),
  );
}

class GoalsListScreen extends ConsumerWidget {
  const GoalsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('plan.goals'.tr())),
      body: _body<GoalItem>(
        async: ref.watch(goalsProvider),
        onRetry: () => ref.invalidate(goalsProvider),
        onRefresh: () async {
          ref.invalidate(goalsProvider);
          await ref.read(goalsProvider.future);
        },
        tile: (g) => _ProgressCard(
          title: g.name,
          value: '${g.current.formatted} / ${g.target.formatted}',
          progress: g.progress,
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
      body: _body<BudgetItem>(
        async: ref.watch(budgetsProvider),
        onRetry: () => ref.invalidate(budgetsProvider),
        onRefresh: () async {
          ref.invalidate(budgetsProvider);
          await ref.read(budgetsProvider.future);
        },
        tile: (b) => _ProgressCard(
          title: b.name,
          value: '${b.spent.formatted} / ${b.limit.formatted}',
          progress: (b.percentage / 100).clamp(0, 1).toDouble(),
          danger: b.isExceeded,
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
      body: _body<LoanItem>(
        async: ref.watch(loansProvider),
        onRetry: () => ref.invalidate(loansProvider),
        onRefresh: () async {
          ref.invalidate(loansProvider);
          await ref.read(loansProvider.future);
        },
        tile: (l) => _LineCard(title: l.name, trailing: l.outstanding.formatted, sub: l.status),
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
      body: _body<InvestmentItem>(
        async: ref.watch(investmentsListProvider),
        onRetry: () => ref.invalidate(investmentsListProvider),
        onRefresh: () async {
          ref.invalidate(investmentsListProvider);
          await ref.read(investmentsListProvider.future);
        },
        tile: (i) => _LineCard(
          title: i.name,
          trailing: i.value.formatted,
          sub: i.gain.formatted,
          subColor: i.gain.isNegative ? Colors.red : null,
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
      body: _body<ProjectItem>(
        async: ref.watch(projectsProvider),
        onRetry: () => ref.invalidate(projectsProvider),
        onRefresh: () async {
          ref.invalidate(projectsProvider);
          await ref.read(projectsProvider.future);
        },
        tile: (p) => _LineCard(
          title: p.name,
          trailing: p.spent.formatted,
          sub: p.budget?.formatted,
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.value,
    required this.progress,
    this.danger = false,
  });

  final String title;
  final String value;
  final double progress;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(value, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHigh,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.title, required this.trailing, this.sub, this.subColor});

  final String title;
  final String trailing;
  final String? sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: sub == null ? null : Text(sub!, style: TextStyle(color: subColor)),
        trailing: Text(trailing, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
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
