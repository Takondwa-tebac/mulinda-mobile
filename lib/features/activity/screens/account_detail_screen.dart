import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money_json.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';
import '../widgets/txn_view.dart';

/// Shows a single account's balance, a standing verdict (good vs overspending),
/// and the full list of transactions originating in that account.
class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(accountTransactionsProvider(account.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'activity2.deleteAccount'.tr(),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _showDeleteDialog(context, ref, account),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountTransactionsProvider(account.id));
          await ref.read(accountTransactionsProvider(account.id).future);
        },
        child: txns.when(
          loading: () => const SkeletonList(header: true, count: 5),
          error: (_, _) => ScrollFill(
            child: ErrorRetry(
              message: 'activity.loadError'.tr(),
              onRetry: () => ref.invalidate(accountTransactionsProvider(account.id)),
            ),
          ),
          data: (list) => _Body(account: account, txns: list),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.account, required this.txns});

  final Account account;
  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final incomeMinor = txns.where((t) => t.isIncome).fold<int>(0, (s, t) => s + t.amount.minorUnits);
    // Only real spending: transfers and "moving my money" are left out.
    final expenseMinor = txns.where((t) => t.countsAsSpending).fold<int>(0, (s, t) => s + t.amount.minorUnits);
    final balanceMinor = account.currentBalance.minorUnits;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _BalanceCard(account: account),
        const SizedBox(height: 16),
        _StandingCard(
          balanceMinor: balanceMinor,
          incomeMinor: incomeMinor,
          expenseMinor: expenseMinor,
          currency: account.currency,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'account.income'.tr(),
                value: formatMoney(incomeMinor / 100, account.currency),
                icon: Icons.south_west,
                accent: context.semantic.income,
                valueColor: context.semantic.income,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatCard(
                label: 'account.spending'.tr(),
                value: formatMoney(expenseMinor / 100, account.currency),
                icon: Icons.north_east,
                accent: context.semantic.expense,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SectionHeader('account.transactions'.tr()),
        if (txns.isEmpty)
          EmptyState(compact: true, icon: Icons.receipt_long_outlined, title: 'account.noTransactions'.tr())
        else
          ...txns.map(
            (t) => TransactionTile(
              data: txnTileData(t, meta: t.occurredLocal == null ? null : dayHeaderLabel(t.occurredLocal)),
              onTap: () => context.push(Routes.transactionDetail, extra: t.id),
            ),
          ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _typeLabel(account.type),
              style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              account.currentBalance.formatted,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 2),
            Text(
              account.pending
                  ? '${'account.balance'.tr()} · ${'activity2.waitingToSync'.tr()}'
                  : account.balanceEstimated
                  ? '${'account.balance'.tr()} · ${'activity2.estimated'.tr()}'
                  : 'account.balance'.tr(),
              style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String t) =>
      t.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class _StandingCard extends StatelessWidget {
  const _StandingCard({
    required this.balanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.currency,
  });

  final int balanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (color, icon, title, body) = _verdict(context, scheme);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: scheme.onSurface, fontSize: 13, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData, String, String) _verdict(BuildContext context, ColorScheme scheme) {
    if (balanceMinor < 0) {
      return (scheme.error, Icons.warning_amber_rounded, 'account.overdrawnTitle'.tr(), 'account.overdrawnBody'.tr());
    }
    if (expenseMinor > incomeMinor && incomeMinor >= 0 && expenseMinor > 0) {
      return (
        context.semantic.warning,
        Icons.trending_down,
        'account.overspendTitle'.tr(),
        'account.overspendBody'.tr(),
      );
    }
    return (scheme.primary, Icons.verified_outlined, 'account.goodTitle'.tr(), 'account.goodBody'.tr());
  }
}

Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref, Account account) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('activity2.deleteAccountTitle'.tr(args: [account.name])),
      content: Text('activity2.deleteAccountBody'.tr()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('common.cancel'.tr())),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
          onPressed: () => Navigator.pop(c, true),
          child: Text('common.delete'.tr()),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    try {
      await ref.read(activityRepositoryProvider).deleteAccount(account.id);
      if (context.mounted) {
        Navigator.of(context).pop();
        ref.invalidate(accountsProvider);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('activity2.accountDeleted'.tr())));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('activity2.accountDeleteFailed'.tr())));
      }
    }
  }
}
