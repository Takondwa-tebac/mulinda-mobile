import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';

/// Shows a single account's balance, a standing verdict (good vs overspending),
/// and the full list of transactions originating in that account.
class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(accountTransactionsProvider(account.id));

    return Scaffold(
      appBar: AppBar(title: Text(account.name, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountTransactionsProvider(account.id));
          await ref.read(accountTransactionsProvider(account.id).future);
        },
        child: txns.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('activity.loadError'.tr())),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(accountTransactionsProvider(account.id)),
                  child: Text('common.retry'.tr()),
                ),
              ),
            ],
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
    final incomeMinor =
        txns.where((t) => t.isIncome).fold<int>(0, (s, t) => s + t.amount.minorUnits);
    final expenseMinor =
        txns.where((t) => !t.isIncome).fold<int>(0, (s, t) => s + t.amount.minorUnits);
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
            Expanded(child: _StatTile(
              label: 'account.income'.tr(),
              value: _money(incomeMinor, account.currency),
              icon: Icons.south_west,
              positive: true,
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(
              label: 'account.spending'.tr(),
              value: _money(expenseMinor, account.currency),
              icon: Icons.north_east,
              positive: false,
            )),
          ],
        ),
        const SizedBox(height: 24),
        Text('account.transactions'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (txns.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text('account.noTransactions'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          )
        else
          ...txns.map((t) => _TxnTile(txn: t)),
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
            Text(_typeLabel(account.type),
                style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 13)),
            const SizedBox(height: 6),
            Text(account.currentBalance.formatted,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
            const SizedBox(height: 2),
            Text('account.balance'.tr(),
                style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8), fontSize: 12)),
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
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
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
      return (scheme.error, Icons.warning_amber_rounded,
          'account.overdrawnTitle'.tr(), 'account.overdrawnBody'.tr());
    }
    if (expenseMinor > incomeMinor && incomeMinor >= 0 && expenseMinor > 0) {
      return (Colors.orange.shade800, Icons.trending_down,
          'account.overspendTitle'.tr(), 'account.overspendBody'.tr());
    }
    return (scheme.primary, Icons.verified_outlined,
        'account.goodTitle'.tr(), 'account.goodBody'.tr());
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.positive,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = positive ? scheme.primary : scheme.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16)),
        ],
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
    final title = txn.merchant?.isNotEmpty == true ? txn.merchant! : (txn.categoryName ?? txn.type);

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
        style: TextStyle(fontWeight: FontWeight.w700, color: txn.isIncome ? scheme.primary : scheme.onSurface),
      ),
      onTap: () => context.push(
        Routes.transactionDetail,
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

/// Format minor units into a currency string (the API only preformats per-txn
/// amounts, so totals are formatted here).
String _money(int minor, String currency) {
  const symbols = {'MWK': 'MK', 'USD': '\$', 'ZAR': 'R', 'KES': 'KSh', 'NGN': '₦'};
  final symbol = symbols[currency] ?? currency;
  final major = minor / 100;
  final whole = major.truncateToDouble() == major;
  final s = major.toStringAsFixed(whole ? 0 : 2);
  final parts = s.split('.');
  final grouped = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return parts.length > 1 ? '$symbol $grouped.${parts[1]}' : '$symbol $grouped';
}
