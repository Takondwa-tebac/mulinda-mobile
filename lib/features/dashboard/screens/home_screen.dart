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
import '../../../core/widgets/transaction_tile.dart';
import '../../activity/data/activity_feed.dart';
import '../../activity/widgets/txn_view.dart';
import '../../auth/providers/auth_controller.dart';
import '../../insights/data/insights_repository.dart';
import '../../plan/data/budget_pace.dart';
import '../../plan/data/plan_models.dart';
import '../../plan/data/plan_repository.dart';
import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';
import '../data/spending_insight.dart';
import '../widgets/spending_chart.dart';
import '../../subscription/widgets/trial_banner.dart';
import '../../../shared/plural.dart';
import '../../../core/theme/app_icons.dart';

/// Home, the command centre: balance, where the money went, what needs
/// attention, budgets at a glance, recent activity, then health and coach.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final firstName = ref.watch(currentUserProvider)?.firstName;
    final unread = ref.watch(unreadInsightsCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('app.name'.tr()),
        actions: [
          IconButton(
            tooltip: 'insights.title'.tr(),
            onPressed: () => context.push(Routes.insights),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            icon: const Icon(AppIcons.coach),
            tooltip: 'home.askCoach'.tr(),
            onPressed: () => context.push(Routes.coach),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(budgetsProvider);
          ref.invalidate(dashboardProvider);
          await ref.read(dashboardProvider.future);
        },
        child: async.when(
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(header: true, count: 4),
          error: (_, _) => ScrollFill(
            child: ErrorRetry(message: 'home.loadError'.tr(), onRetry: () => ref.invalidate(dashboardProvider)),
          ),
          data: (d) => _Dashboard(data: d, firstName: firstName),
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.data, this.firstName});

  final DashboardSummary data;
  final String? firstName;

  void _openNeedsCategory(BuildContext context, WidgetRef ref) {
    ref.read(activityFilterProvider.notifier).showNeedsCategory();
    context.go(Routes.activity);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final greeting = firstName == null || firstName!.isEmpty
        ? 'home.greeting'.tr()
        : '${'home.greeting'.tr()}, $firstName';
    final needs = data.needsAttention ?? 0;
    final spending = data.spendingByCategory.where((r) => r.amount.minorUnits > 0).toList();

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        Text(greeting, style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.lg),
        _BalanceHero(data: data),
        const SizedBox(height: AppSpacing.lg),

        // Renders nothing unless a free trial is running.
        const TrialBanner(margin: EdgeInsets.only(bottom: AppSpacing.lg)),

        if (data.isFirstRun) ...[const _FirstRunCard(), const SizedBox(height: AppSpacing.lg)],

        if (needs > 0) ...[
          _AttentionCard(count: needs, onTap: () => _openNeedsCategory(context, ref)),
          const SizedBox(height: AppSpacing.lg),
        ],

        if (spending.isNotEmpty) ...[
          _WhereMoneyWent(
            rows: spending,
            needsAttention: needs,
            onSortCategories: () => _openNeedsCategory(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        _BudgetsAtAGlance(total: data.budgetsTotal),

        if (!data.isFirstRun) ...[
          SectionHeader(
            'home.recentActivity'.tr(),
            actionLabel: 'home2.seeAll'.tr(),
            onAction: () {
              ref.read(activityFilterProvider.notifier).reset();
              context.go(Routes.activity);
            },
          ),
          if (data.recent.isEmpty)
            EmptyState(
              compact: true,
              icon: Icons.receipt_long_outlined,
              title: 'home.noTransactions'.tr(),
              actionLabel: 'activity2.addTransaction'.tr(),
              onAction: () => context.push(Routes.addTransaction),
            )
          else
            ...data.recent.map(
              (t) => TransactionTile(
                data: _recentTile(t),
                onTap: () => context.push(Routes.transactionById(t.id)),
                onConfirmCategory: () => context.push(Routes.transactionById(t.id)),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],

        SectionHeader('home2.yourHealth'.tr()),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatCard(
                  centered: true,
                  icon: Icons.favorite_rounded,
                  label: 'home.health'.tr(),
                  value: '${data.indicators.healthScore}',
                  caption: data.indicators.healthGrade,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  centered: true,
                  icon: Icons.verified_rounded,
                  label: 'home.credit'.tr(),
                  value: '${data.indicators.creditScore}',
                  caption: data.indicators.creditBand,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  centered: true,
                  icon: Icons.savings_rounded,
                  label: 'home.savings'.tr(),
                  value: data.indicators.savingsOnTrack ? 'home.onTrack'.tr() : 'home.offTrack'.tr(),
                  valueColor: data.indicators.savingsOnTrack ? context.semantic.success : context.semantic.danger,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _CoachCard(onTap: () => context.push(Routes.coach)),
        const SizedBox(height: AppSpacing.lg),

        // Quick stats → their own lists.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatCard(
                  label: 'home.budgets'.tr(),
                  value: '${data.budgetsTotal}',
                  caption: data.budgetsExceeded > 0 ? 'home2.overCount'.tr(args: ['${data.budgetsExceeded}']) : null,
                  captionColor: context.semantic.danger,
                  highlight: data.budgetsExceeded > 0,
                  accent: data.budgetsExceeded > 0 ? context.semantic.danger : null,
                  icon: Icons.pie_chart_outline,
                  onTap: () => context.push(Routes.budgets),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  label: 'home.goals'.tr(),
                  value: '${data.goalsActive}',
                  icon: Icons.flag_outlined,
                  onTap: () => context.push(Routes.goals),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatCard(
                  label: 'home.loans'.tr(),
                  value: data.loansOutstanding.formatted,
                  icon: Icons.account_balance_outlined,
                  onTap: () => context.push(Routes.loans),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  label: 'home.investments'.tr(),
                  value: data.investmentsValue.formatted,
                  icon: Icons.trending_up,
                  onTap: () => context.push(Routes.investments),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TransactionTileData _recentTile(RecentTxn t) {
    final day = DateTime.tryParse(t.date);
    // Bank references are never shown as a name (see displayName).
    final named = (t.merchant?.trim().isNotEmpty ?? false) && !looksLikeReference(t.merchant);
    final title = named ? t.merchant!.trim() : (t.category ?? displayName(type: t.type, merchant: t.merchant));
    return TransactionTileData(
      id: t.id,
      title: title,
      amount: t.amount,
      type: t.type,
      categoryName: t.category,
      categoryIcon: t.categoryIcon,
      categoryColor: t.categoryColor,
      meta: day == null ? t.date : dayHeaderLabel(day),
      needsAttention: t.needsAttention,
      notSpending: t.notSpending,
    );
  }
}

/// Net worth, with this month's money in and out underneath.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.data});

  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final on = scheme.onPrimary;
    final month = data.thisMonth;
    final rate = (month.savingsRate * 100).clamp(-999, 999).toStringAsFixed(0);

    Widget figure(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 12)),
          const SizedBox(height: AppSpacing.xxs),
          // Shrinks to fit rather than cutting the amount off.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(color: on, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl - 4),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('home.netWorth'.tr(), style: TextStyle(color: on.withValues(alpha: 0.85))),
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.netWorth.formatted,
            style: text.headlineMedium?.copyWith(color: on, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(height: 1, color: on.withValues(alpha: 0.15)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              figure('home2.inThisMonth'.tr(), month.income.formatted),
              const SizedBox(width: AppSpacing.md),
              figure('home2.outThisMonth'.tr(), month.expense.formatted),
              const SizedBox(width: AppSpacing.md),
              figure('home.savingsRate'.tr(), '$rate%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WhereMoneyWent extends StatelessWidget {
  const _WhereMoneyWent({required this.rows, required this.needsAttention, required this.onSortCategories});

  final List<CategorySpend> rows;
  final int needsAttention;
  final VoidCallback onSortCategories;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insight = spendingInsight(rows);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader('home2.whereMoneyWent'.tr(), padding: const EdgeInsets.only(bottom: AppSpacing.xxs)),
            Text('home2.monthToDate'.tr(), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            SpendingChart(rows: rows),
            if (uncategorisedShare(rows) >= 0.4 && needsAttention > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Material(
                color: context.semantic.warningContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: onSortCategories,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(Icons.category_outlined, size: 18, color: context.semantic.warning),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text('home2.mostlyUncategorised'.tr(), style: const TextStyle(fontSize: 13))),
                        Icon(Icons.chevron_right, size: 18, color: context.semantic.warning),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (insight != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(
                    insight.up ? Icons.trending_up : Icons.trending_down,
                    size: 18,
                    color: insight.up ? context.semantic.warning : context.semantic.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      (insight.up ? 'home2.insightUp' : 'home2.insightDown').tr(
                        args: [insight.categoryName, '${insight.percent}'],
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    return Material(
      color: s.warningContainer,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(AppIcons.suggestion, color: s.warning),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home2.needsAttention'.tr(),
                      style: TextStyle(fontWeight: FontWeight.w700, color: s.warning),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(trCount('home2.needsAttentionBody', count), style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: s.warning),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three budgets closest to (or past) their limit.
class _BudgetsAtAGlance extends ConsumerWidget {
  const _BudgetsAtAGlance({required this.total});

  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
            leading: const Icon(Icons.pie_chart_outline),
            title: Text('home2.noBudgetsTitle'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('home2.noBudgetsBody'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.plan),
          ),
        ),
      );
    }
    final budgets = ref.watch(budgetsProvider);
    return budgets.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (list) {
        final active = list.where((b) => b.isActive).toList()..sort((a, b) => _share(b).compareTo(_share(a)));
        if (active.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                'home2.budgetsGlance'.tr(),
                actionLabel: 'home2.seeAll'.tr(),
                onAction: () => context.push(Routes.budgets),
              ),
              Card(
                child: Column(children: [for (final b in active.take(3)) _GlanceRow(budget: b)]),
              ),
            ],
          ),
        );
      },
    );
  }

  static double _share(BudgetItem b) => b.limit.minorUnits > 0 ? b.spent.minorUnits / b.limit.minorUnits : 0;
}

class _GlanceRow extends StatelessWidget {
  const _GlanceRow({required this.budget});

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
    final paceLabel = pace.health == BudgetHealth.over
        ? 'plan2.status.over'.tr()
        : pace.elapsedShare == null
        ? null
        : (pace.overPace ? 'home2.overPace'.tr() : 'home2.onPace'.tr());
    final paceColor = switch (pace.health) {
      BudgetHealth.over => context.semantic.danger,
      _ => pace.overPace ? context.semantic.warning : context.semantic.success,
    };
    return InkWell(
      onTap: () => context.push(Routes.budgetById(b.id), extra: b),
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
                if (paceLabel != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    paceLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: paceColor),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ProgressBar(value: pace.spentShare, health: pace.health, semanticsLabel: b.name),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'plan2.spentOf'.tr(args: [b.spent.formatted, b.limit.formatted]),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        leading: CircleAvatar(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          child: const Icon(AppIcons.coachFilled),
        ),
        title: Text(
          'home.askCoach'.tr(),
          style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
        ),
        subtitle: Text(
          'home.askCoachSub'.tr(),
          style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
        onTap: onTap,
      ),
    );
  }
}

/// Shown until anything has been recorded: the three ways to get started.
class _FirstRunCard extends StatelessWidget {
  const _FirstRunCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget step(IconData icon, String title, String body, String route) => ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(body),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
              child: Text(
                'home2.getStartedTitle'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text('home2.getStartedBody'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: AppSpacing.sm),
            step(
              Icons.account_balance_wallet_outlined,
              'home2.stepAccount'.tr(),
              'home2.stepAccountSub'.tr(),
              Routes.addAccount,
            ),
            step(Icons.sms_outlined, 'home2.stepSms'.tr(), 'home2.stepSmsSub'.tr(), Routes.pasteSms),
            step(Icons.edit_outlined, 'home2.stepManual'.tr(), 'home2.stepManualSub'.tr(), Routes.addTransaction),
          ],
        ),
      ),
    );
  }
}
