import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../activity/widgets/txn_view.dart';
import '../../auth/providers/auth_controller.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/widgets/spending_chart.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/widgets/premium_lock.dart';
import '../data/budget_pace.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';
import 'plan_forms.dart';

/// Plan as a dashboard: this month's budgets at a glance, each budget's pace,
/// goals, then commitments (loans, investments, projects) and the advisory.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(budgetsProvider)
      ..invalidate(goalsProvider)
      ..invalidate(advisoryProvider)
      ..invalidate(dashboardProvider);
    await Future.wait([
      ref.read(budgetsProvider.future).catchError((_) => <BudgetItem>[]),
      ref.read(goalsProvider.future).catchError((_) => <GoalItem>[]),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);
    final goals = ref.watch(goalsProvider);
    final dashboard = ref.watch(dashboardProvider).valueOrNull;
    // Advisory (savings-rule / creditworthiness / investing) is premium.
    final canSeeAdvisory = ref.watch(currentUserProvider)?.can(Entitlements.advancedInsights) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('nav.plan'.tr()),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('plan-add-menu'),
            tooltip: 'plan2.createMenu'.tr(),
            icon: const Icon(Icons.add),
            onSelected: (route) => route == Routes.budgetForm ? openBudgetForm(context) : context.push(route),
            itemBuilder: (_) => [
              for (final (route, icon, label) in [
                (Routes.budgetForm, Icons.pie_chart_outline, 'plan2.newBudget'),
                (Routes.goalForm, Icons.flag_outlined, 'plan2.newGoal'),
                (Routes.loanForm, Icons.account_balance_outlined, 'plan2.newLoan'),
                (Routes.investmentForm, Icons.trending_up, 'plan2.newInvestment'),
                (Routes.projectForm, Icons.home_work_outlined, 'plan2.newProject'),
              ])
                PopupMenuItem<String>(
                  value: route,
                  child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label.tr())]),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            budgets.when(
              loading: () => const Shimmer(child: SkeletonBox(height: 140, radius: AppRadius.lg)),
              error: (_, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ErrorRetry(
                    compact: true,
                    message: 'plan.loadError'.tr(),
                    onRetry: () => ref.invalidate(budgetsProvider),
                  ),
                ),
              ),
              data: (list) => _BudgetsSection(
                budgets: list.where((b) => b.isActive).toList(),
                spending: dashboard?.spendingByCategory ?? const [],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              'plan.goals'.tr(),
              actionLabel: 'home2.seeAll'.tr(),
              onAction: () => context.push(Routes.goals),
            ),
            goals.when(
              loading: () => const Shimmer(child: SkeletonBox(height: 72, radius: AppRadius.lg)),
              error: (_, _) => ErrorRetry(compact: true, onRetry: () => ref.invalidate(goalsProvider)),
              data: (list) => list.isEmpty
                  ? Card(
                      child: EmptyState(
                        compact: true,
                        icon: Icons.flag_outlined,
                        title: 'plan2.noGoalsTitle'.tr(),
                        body: 'plan2.noGoalsBody'.tr(),
                        actionLabel: 'plan2.newGoal'.tr(),
                        onAction: () => context.push(Routes.goalForm),
                      ),
                    )
                  : Card(
                      child: Column(children: [for (final g in list.take(4)) _GoalRow(goal: g)]),
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader('plan2.commitments'.tr()),
            _CommitmentTiles(data: dashboard),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader('plan.advisory'.tr()),
            if (!canSeeAdvisory)
              PremiumUpsellCard(
                title: 'plan.advisoryLockedTitle'.tr(),
                message: 'plan.advisoryLockedMessage'.tr(),
                icon: Icons.insights_rounded,
                compact: true,
              )
            else
              ref
                  .watch(advisoryProvider)
                  .when(
                    loading: () => const Shimmer(child: SkeletonBox(height: 90, radius: AppRadius.lg)),
                    error: (_, _) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: ErrorRetry(
                          compact: true,
                          message: 'plan2.advisoryError'.tr(),
                          onRetry: () => ref.invalidate(advisoryProvider),
                        ),
                      ),
                    ),
                    data: (a) => _Advisory(summary: a, onRetry: () => ref.invalidate(advisoryProvider)),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Opens the budget form, optionally prefilled with a category.
/// Always on the root navigator, so the form covers the whole screen (no
/// bottom bar or capture button over it).
Future<void> openBudgetForm(BuildContext context, {String? categoryId, String? name}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => BudgetForm(initialCategoryId: categoryId, initialName: name),
    ),
  );
}

/// "This month" ring and totals, then one row per budget, then suggestions for
/// spending categories that have no budget yet.
class _BudgetsSection extends StatelessWidget {
  const _BudgetsSection({required this.budgets, required this.spending});

  final List<BudgetItem> budgets;
  final List<CategorySpend> spending;

  @override
  Widget build(BuildContext context) {
    final budgeted = budgets.map((b) => b.categoryId).whereType<String>().toSet();
    final suggestions = spending
        .where((s) => s.categoryId != null && !budgeted.contains(s.categoryId) && s.amount.minorUnits > 0)
        .take(3)
        .toList();

    if (budgets.isEmpty) {
      return Column(
        children: [
          Card(
            child: EmptyState(
              compact: true,
              icon: Icons.pie_chart_outline,
              title: 'plan2.noBudgetsTitle'.tr(),
              body: 'plan2.noBudgetsBody'.tr(),
              actionLabel: 'plan2.createBudget'.tr(),
              onAction: () => openBudgetForm(context),
            ),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _Suggestions(rows: suggestions),
            ),
          ],
        ],
      );
    }

    // Totals only make sense in one currency; use the most common one.
    final byCurrency = <String, List<BudgetItem>>{};
    for (final b in budgets) {
      byCurrency.putIfAbsent(b.limit.currency, () => []).add(b);
    }
    final main = byCurrency.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);
    final limit = main.value.fold<int>(0, (s, b) => s + b.limit.minorUnits);
    final spent = main.value.fold<int>(0, (s, b) => s + b.spent.minorUnits);

    final sorted = [...budgets]
      ..sort((a, b) {
        double share(BudgetItem x) => x.limit.minorUnits > 0 ? x.spent.minorUnits / x.limit.minorUnits : 0;
        return share(b).compareTo(share(a));
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ThisMonthCard(currency: main.key, limitMinor: limit, spentMinor: spent),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(
          'plan.budgets'.tr(),
          actionLabel: 'home2.seeAll'.tr(),
          onAction: () => context.push(Routes.budgets),
        ),
        Card(
          child: Column(children: [for (final b in sorted.take(6)) _BudgetRow(budget: b)]),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: _Suggestions(rows: suggestions),
          ),
        ],
      ],
    );
  }
}

class _ThisMonthCard extends StatelessWidget {
  const _ThisMonthCard({required this.currency, required this.limitMinor, required this.spentMinor});

  final String currency;
  final int limitMinor;
  final int spentMinor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = limitMinor > 0 ? spentMinor / limitMinor : 0.0;
    final remaining = limitMinor - spentMinor;
    final over = remaining < 0;
    final color = over
        ? context.semantic.danger
        : share >= 0.8
        ? ProgressBar.colorFor(context, BudgetHealth.atRisk)
        : scheme.primary;

    Widget figure(String label, String value, {Color? valueColor}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w700, color: valueColor),
              ),
            ),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            RingProgress(
              value: share,
              color: color,
              center: Text(
                '${(share * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'plan2.thisPeriod'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  figure('plan2.budgeted'.tr(), formatMinor(limitMinor, currency)),
                  figure('plan2.spent'.tr(), formatMinor(spentMinor, currency)),
                  figure(
                    over ? 'plan2.overBy'.tr() : 'plan2.remaining'.tr(),
                    formatMinor(remaining.abs(), currency),
                    valueColor: over ? context.semantic.danger : context.semantic.success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.budget});

  final BudgetItem budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = budget;
    final pace = budgetPace(
      spentMinor: b.spent.minorUnits,
      limitMinor: b.limit.minorUnits,
      from: b.periodFrom,
      to: b.periodTo,
      alertThreshold: b.alertThreshold,
    );
    final remaining = b.limit.minorUnits - b.spent.minorUnits;
    final currency = b.limit.currency;
    final (label, tone) = switch (pace.health) {
      BudgetHealth.over => ('plan2.status.over'.tr(), StatusTone.danger),
      BudgetHealth.atRisk => ('plan2.status.atRisk'.tr(), StatusTone.warning),
      BudgetHealth.onTrack => ('plan2.status.onTrack'.tr(), StatusTone.success),
    };
    final projected = pace.projectedMinor;

    return InkWell(
      onTap: () => context.push(Routes.budgetDetail, extra: b),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    b.name.isEmpty ? (b.categoryName ?? 'budgetSpend.budget'.tr()) : b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                StatusChip(label: label, tone: tone),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ProgressBar(value: pace.spentShare, health: pace.health, semanticsLabel: b.name),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _Figure(label: 'plan2.planned'.tr(), value: b.limit.formatted),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Figure(label: 'plan2.spent'.tr(), value: b.spent.formatted),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Figure(
                    label: remaining < 0 ? 'plan2.overBy'.tr() : 'plan2.remaining'.tr(),
                    value: formatMinor(remaining.abs(), currency),
                    color: remaining < 0 ? context.semantic.danger : null,
                    end: true,
                  ),
                ),
              ],
            ),
            if (projected != null && pace.health != BudgetHealth.over && b.periodTo != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'plan2.projected'.tr(args: [formatMinor(projected, currency)]),
                style: TextStyle(
                  fontSize: 12,
                  color: projected > b.limit.minorUnits ? context.semantic.warning : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color, this.end = false});

  final String label;
  final String value;
  final Color? color;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }
}

/// "You've spent MK x on Transport this month — set a budget?"
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.rows});

  final List<CategorySpend> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      // Full width, like the cards around it.
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'plan2.suggestTitle'.tr(),
              style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text('plan2.suggestBody'.tr(), style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (var i = 0; i < rows.length; i++)
                  ActionChip(
                    avatar: Icon(Icons.add, size: 18, color: spendColor(rows[i], i)),
                    label: Text('${rows[i].name} · ${rows[i].amount.formatted}'),
                    onPressed: () => openBudgetForm(context, categoryId: rows[i].categoryId, name: rows[i].name),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A goal with its progress, what is left, and a modest note at 50% / 100%.
class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});

  final GoalItem goal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = goal;
    final p = g.progress;
    final left = g.target.minorUnits - g.current.minorUnits;
    final done = p >= 1;
    final milestone = done
        ? 'plan2.milestoneDone'.tr()
        : p >= 0.5
        ? 'plan2.milestoneHalf'.tr()
        : null;

    return InkWell(
      onTap: () => context.push(Routes.goalDetail, extra: g),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${(p * 100).round()}%',
                  style: TextStyle(fontWeight: FontWeight.w700, color: context.semantic.brandInk),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Goal-gradient: the bar gets a stronger colour as it nears the end.
            ProgressBar(
              value: p,
              color: Color.lerp(scheme.primary.withValues(alpha: 0.55), scheme.primary, p),
              semanticsLabel: g.name,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    done
                        ? 'plan2.saved'.tr(args: [g.current.formatted])
                        : 'plan2.toGo'.tr(args: [formatMinor(left, g.target.currency)]),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                if (milestone != null) ...[
                  Icon(Icons.check_circle, size: 14, color: context.semantic.success),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    milestone,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.semantic.success),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Loans, investments and projects as compact entry tiles.
class _CommitmentTiles extends StatelessWidget {
  const _CommitmentTiles({required this.data});

  final DashboardSummary? data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.account_balance_outlined,
                label: 'plan.loans'.tr(),
                value: d == null ? '–' : d.loansOutstanding.formatted,
                caption: d == null ? null : 'plan2.activeCount'.tr(args: ['${d.loansActive}']),
                onTap: () => context.push(Routes.loans),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatCard(
                icon: Icons.trending_up,
                label: 'plan.investments'.tr(),
                value: d == null ? '–' : d.investmentsValue.formatted,
                caption: d == null ? null : 'plan2.holdingsCount'.tr(args: ['${d.investmentsCount}']),
                onTap: () => context.push(Routes.investments),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.home_work_outlined,
                label: 'plan.projects'.tr(),
                value: d == null ? '–' : '${d.projectsActive}',
                caption: 'plan2.active'.tr(),
                onTap: () => context.push(Routes.projects),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatCard(
                icon: Icons.pie_chart_outline,
                label: 'plan.budgets'.tr(),
                value: d == null ? '–' : '${d.budgetsTotal}',
                caption: 'plan2.allBudgets'.tr(),
                onTap: () => context.push(Routes.budgets),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Advisory extends StatelessWidget {
  const _Advisory({required this.summary, required this.onRetry});
  final AdvisorySummary summary;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reco = summary.investRecommendation;
    final posture = summary.riskPosture;
    final target = summary.targetRate;
    // Every advisory endpoint failed (they degrade to null individually).
    final nothing =
        summary.savingsRuleName == null &&
        summary.savingsOnTrack == null &&
        summary.creditScore == null &&
        reco == null;
    if (nothing) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorRetry(compact: true, message: 'plan2.advisoryError'.tr(), onRetry: onRetry),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'plan.savingsRule'.tr(),
                value: summary.savingsRuleName ?? '–',
                caption: summary.savingsOnTrack == null
                    ? null
                    : (summary.savingsOnTrack! ? 'plan.onTrack'.tr() : 'plan.offTrack'.tr()),
                captionColor: summary.savingsOnTrack == true ? context.semantic.success : context.semantic.danger,
                icon: Icons.savings_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatCard(
                label: 'plan.creditworthiness'.tr(),
                value: summary.creditScore?.toString() ?? '–',
                caption: summary.creditBand,
                icon: Icons.verified_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        StatCard(
          label: 'plan.investing'.tr(),
          value: reco == null ? '–' : 'plan.reco.$reco'.tr(),
          caption: [
            if (posture != null) 'plan.posture.$posture'.tr(),
            if (target != null) '${(target * 100).toStringAsFixed(0)}%',
          ].join(' · '),
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('plan.notAdvice'.tr(), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
