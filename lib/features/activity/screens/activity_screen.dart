import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../capture/data/inbox_repository.dart';
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
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Badge(
              isLabelVisible: pending > 0 || reviewCount > 0,
              child: const Icon(Icons.more_vert),
            ),
            onSelected: (v) => context.push(switch (v) {
              'review' => Routes.review,
              'export' => Routes.exports,
              _ => Routes.inbox,
            }),
            itemBuilder: (_) => [
              _menuItem('review', Icons.fact_check_outlined, 'Review auto-recorded',
                  count: reviewCount),
              _menuItem('inbox', Icons.inbox_outlined, 'inbox.title'.tr(), count: pending),
              _menuItem('export', Icons.ios_share_outlined, 'Export records'),
            ],
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
              // Surfaces itself only when there's something to review.
              if (reviewCount > 0) ...[
                _ReviewBanner(count: reviewCount, onTap: () => context.push(Routes.review)),
                const SizedBox(height: 16),
              ],
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

/// A labeled overflow-menu row, optionally with a count pill.
PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {int count = 0}) {
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
        if (count > 0) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.rectangle,
                borderRadius: BorderRadius.all(Radius.circular(20))),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    ),
  );
}

/// Prominent, self-surfacing prompt to review auto-recorded transactions.
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.fact_check_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$count transaction${count == 1 ? '' : 's'} to review',
                        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                    const SizedBox(height: 2),
                    Text('Auto-recorded from your SMS — tap to confirm or remove',
                        style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
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
      // The detail screen fetches full detail (incl. source SMS) by id.
      onTap: () => context.push(Routes.transactionDetail, extra: txn.id),
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
