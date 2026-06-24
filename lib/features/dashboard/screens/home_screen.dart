import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../../insights/data/insights_repository.dart';
import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

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
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'home.askCoach'.tr(),
            onPressed: () => context.push(Routes.coach),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: async.when(
          loading: () => const _Scrollable(child: _CenterBox(child: CircularProgressIndicator())),
          error: (_, _) => _Scrollable(
            child: _CenterBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('home.loadError'.tr(), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => ref.invalidate(dashboardProvider),
                    child: Text('home.retry'.tr()),
                  ),
                ],
              ),
            ),
          ),
          data: (d) => _Dashboard(data: d, firstName: firstName),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.data, this.firstName});

  final DashboardSummary data;
  final String? firstName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final greeting = firstName == null || firstName!.isEmpty
        ? 'home.greeting'.tr()
        : '${'home.greeting'.tr()}, $firstName';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text(greeting, style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),

        // Net worth hero
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('home.netWorth'.tr(),
                  style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85))),
              const SizedBox(height: 6),
              Text(data.netWorth.formatted,
                  style: text.headlineMedium?.copyWith(
                      color: scheme.onPrimary, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // This month cashflow
        _MonthCard(month: data.thisMonth),
        const SizedBox(height: 16),

        // Indicators
        Row(
          children: [
            Expanded(child: _Indicator(
              label: 'home.health'.tr(),
              value: '${data.indicators.healthScore}',
              badge: data.indicators.healthGrade,
              icon: Icons.favorite_rounded,
            )),
            const SizedBox(width: 12),
            Expanded(child: _Indicator(
              label: 'home.credit'.tr(),
              value: '${data.indicators.creditScore}',
              badge: data.indicators.creditBand,
              icon: Icons.verified_rounded,
            )),
            const SizedBox(width: 12),
            Expanded(child: _Indicator(
              label: 'home.savings'.tr(),
              value: data.indicators.savingsOnTrack ? 'home.onTrack'.tr() : 'home.offTrack'.tr(),
              valueColor: data.indicators.savingsOnTrack ? scheme.primary : scheme.error,
              icon: Icons.savings_rounded,
            )),
          ],
        ),
        const SizedBox(height: 16),

        // Coach entry
        Card(
          color: scheme.primaryContainer,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: const Icon(Icons.auto_awesome),
            ),
            title: Text('home.askCoach'.tr(),
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
            subtitle: Text('home.askCoachSub'.tr(),
                style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
            trailing: Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            onTap: () => context.push(Routes.coach),
          ),
        ),
        const SizedBox(height: 16),

        // Quick stats → Plan
        Row(children: [
          Expanded(child: _Stat(
            label: 'home.budgets'.tr(),
            value: '${data.budgetsTotal}',
            warn: data.budgetsExceeded > 0,
            icon: Icons.pie_chart_outline,
            onTap: () => context.go(Routes.plan),
          )),
          const SizedBox(width: 12),
          Expanded(child: _Stat(
            label: 'home.goals'.tr(),
            value: '${data.goalsActive}',
            icon: Icons.flag_outlined,
            onTap: () => context.go(Routes.plan),
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Stat(
            label: 'home.loans'.tr(),
            value: data.loansOutstanding.formatted,
            icon: Icons.account_balance_outlined,
            onTap: () => context.go(Routes.plan),
          )),
          const SizedBox(width: 12),
          Expanded(child: _Stat(
            label: 'home.investments'.tr(),
            value: data.investmentsValue.formatted,
            icon: Icons.trending_up,
            onTap: () => context.go(Routes.plan),
          )),
        ]),
        const SizedBox(height: 24),

        // Recent activity
        Text('home.recentActivity'.tr(),
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (data.recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('home.noTransactions'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          ...data.recent.map((t) => _TxnTile(txn: t)),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.month});
  final MonthSummary month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = (month.savingsRate * 100).clamp(-999, 999).toStringAsFixed(0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('home.thisMonth'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('$rate% ${'home.savingsRate'.tr()}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _MoneyCol(label: 'home.income'.tr(), value: month.income.formatted, color: scheme.primary),
                const SizedBox(width: 16),
                _MoneyCol(label: 'home.expenses'.tr(), value: month.expense.formatted, color: scheme.secondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyCol extends StatelessWidget {
  const _MoneyCol({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.label,
    required this.value,
    this.badge,
    this.valueColor,
    required this.icon,
  });

  final String label;
  final String value;
  final String? badge;
  final Color? valueColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(height: 8),
          Text(value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: valueColor)),
          if (badge != null)
            Text(badge!, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.warn = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: warn ? Border.all(color: scheme.error, width: 1.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(height: 10),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});
  final RecentTxn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = txn.merchant?.isNotEmpty == true
        ? txn.merchant!
        : (txn.category ?? txn.type);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push(Routes.transactionDetail, extra: txn),
      leading: CircleAvatar(
        backgroundColor: txn.isIncome
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh,
        foregroundColor: txn.isIncome ? scheme.onPrimaryContainer : scheme.onSurface,
        child: Icon(txn.isIncome ? Icons.south_west : Icons.north_east, size: 18),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([txn.category, txn.date].where((e) => e != null && e.isNotEmpty).join(' · ')),
      trailing: Text(
        '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: txn.isIncome ? scheme.primary : scheme.onSurface,
        ),
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: MediaQuery.of(context).size.height * 0.6, child: child)],
    );
  }
}

class _CenterBox extends StatelessWidget {
  const _CenterBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: child));
}
