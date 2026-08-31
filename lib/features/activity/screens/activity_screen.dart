import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../capture/data/inbox_repository.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider);
    final pending = ref.watch(pendingCountProvider);
    final reviewCount = ref.watch(reviewCountProvider).maybeWhen(data: (n) => n, orElse: () => 0);

    return Scaffold(
      appBar: AppBar(
        title: Text('nav.activity'.tr()),
        actions: [
          IconButton(
            tooltip: 'Review auto-recorded',
            onPressed: () => context.push(Routes.review),
            icon: Badge(
              isLabelVisible: reviewCount > 0,
              label: Text('$reviewCount'),
              child: const Icon(Icons.fact_check_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Export records',
            onPressed: () => context.push(Routes.exports),
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: 'inbox.title'.tr(),
            onPressed: () => context.push(Routes.inbox),
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.inbox_outlined),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(transactionsProvider);
          await ref.read(transactionsProvider.future);
        },
        child: txns.when(
          loading: () => const _Fill(child: CircularProgressIndicator()),
          error: (_, _) => _Fill(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('activity.loadError'.tr(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(transactionsProvider),
                  child: Text('activity.retry'.tr()),
                ),
              ],
            ),
          ),
          data: (list) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              accounts.maybeWhen(
                data: (a) => _AccountsStrip(
                  accounts: a,
                  onAdded: () => ref.invalidate(accountsProvider),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text('activity.noTransactions'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                )
              else
                ...list.map((t) => _TxnTile(txn: t)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountsStrip extends StatelessWidget {
  const _AccountsStrip({required this.accounts, required this.onAdded});
  final List<Account> accounts;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('activity.accounts'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextButton.icon(
              onPressed: () => _addAccount(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text('account.add'.tr()),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // +1 for the trailing "add account" tile.
            itemCount: accounts.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              if (i == accounts.length) return _AddAccountTile(onTap: () => _addAccount(context));
              final a = accounts[i];
              return InkWell(
                onTap: () => context.push(Routes.accountDetail, extra: a),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 180,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onPrimaryContainer)),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: scheme.onPrimaryContainer),
                        ],
                      ),
                      Text(a.currentBalance.formatted,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: scheme.onPrimaryContainer)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addAccount(BuildContext context) async {
    final added = await context.push<bool>(Routes.addAccount);
    if (added == true) onAdded();
  }
}

class _AddAccountTile extends StatelessWidget {
  const _AddAccountTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: scheme.primary),
            const SizedBox(height: 8),
            Text('account.add'.tr(),
                style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = txn.merchant?.isNotEmpty == true
        ? txn.merchant!
        : (txn.categoryName ?? txn.type);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: txn.isIncome ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        foregroundColor: txn.isIncome ? scheme.onPrimaryContainer : scheme.onSurface,
        child: Icon(txn.isIncome ? Icons.south_west : Icons.north_east, size: 18),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([txn.categoryName, txn.date].where((e) => e != null && e.isNotEmpty).join(' · ')),
      trailing: Text(
        '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: txn.isIncome ? scheme.primary : scheme.onSurface,
        ),
      ),
      onTap: () => context.push(
        Routes.transactionDetail,
        // The detail/receipt screen takes the dashboard RecentTxn shape.
        extra: RecentTxn(
          id: txn.id,
          date: txn.date,
          type: txn.type,
          amount: txn.amount,
          merchant: txn.merchant,
          category: txn.categoryName,
        ),
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(child: Padding(padding: const EdgeInsets.all(24), child: child)),
        ),
      ],
    );
  }
}
