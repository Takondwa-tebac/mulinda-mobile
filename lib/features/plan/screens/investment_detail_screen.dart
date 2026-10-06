import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';

/// Investment detail. For interest-bearing holdings (fixed deposit, treasury
/// bill/bond) it projects the maturity value and shows the estimated value
/// *today* based on interest accrued pro-rata over the elapsed term.
class InvestmentDetailScreen extends ConsumerWidget {
  const InvestmentDetailScreen({super.key, required this.investment});
  final InvestmentItem investment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref
        .watch(investmentsListProvider)
        .maybeWhen(
          data: (list) => list.firstWhere(
            (e) => e.id == investment.id,
            orElse: () => investment,
          ),
          orElse: () => investment,
        );

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final maturity = DateTime.tryParse(inv.maturityDate ?? '');
    final rate = inv.expectedReturn; // annual, as a fraction (e.g. 0.0575)
    final accrual = inv.accrual; // computed by the API

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'form.edit'.tr(),
            onPressed: () => context.push(Routes.investmentForm, extra: inv),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'form.delete'.tr(),
            onPressed: () => _delete(context, ref, inv),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // Current value card
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'invest.type.${inv.type}'.tr(),
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      inv.value.formatted,
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      inv.isEstimated
                          ? '${'invest.currentValue'.tr()} · ${'invest.estimated'.tr()}'
                          : 'invest.currentValue'.tr(),
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    if (inv.isEstimated) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${'invest.interestSoFar'.tr()}: ${inv.gain.formatted}',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (accrual != null)
              _ProjectionCard(accrual: accrual, maturity: maturity),

            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.savings_outlined,
                    label: 'invest.amountInvested'.tr(),
                    value: inv.amountInvested.formatted,
                  ),
                  if (rate != null)
                    _InfoRow(
                      icon: Icons.percent,
                      label: 'invest.annualRate'.tr(),
                      value: '${(rate * 100).toStringAsFixed(2)}%',
                    ),
                  if (inv.startedAt != null)
                    _InfoRow(
                      icon: Icons.event_outlined,
                      label: 'invest.started'.tr(),
                      value: inv.startedAt!,
                    ),
                  if (inv.maturityDate != null)
                    _InfoRow(
                      icon: Icons.event_available_outlined,
                      label: 'invest.maturity'.tr(),
                      value: inv.maturityDate!,
                    ),
                  _InfoRow(
                    icon: Icons.flag_outlined,
                    label: 'form.status'.tr(),
                    value: 'form.investStatus.${inv.status}'.tr(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    InvestmentItem inv,
  ) async {
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
      await ref.read(planRepositoryProvider).deleteInvestment(inv.id);
      ref.invalidate(investmentsListProvider);
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

class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.accrual, required this.maturity});

  /// Interest figures calculated by the API (same numbers as the list card).
  final InvestmentAccrual accrual;
  final DateTime? maturity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = accrual.progress.clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'invest.maturityProjection'.tr(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              accrual.matured || maturity == null
                  ? 'invest.matured'.tr()
                  : 'invest.maturesOn'.tr(
                      args: [_fmtDate(maturity!), '${accrual.daysToMaturity}'],
                    ),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: scheme.surfaceContainerHigh,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Today vs maturity estimates.
            _EstRow(
              label: 'invest.estToday'.tr(),
              value: accrual.estimatedValue.formatted,
              sub: '${'invest.interestSoFar'.tr()}: ${accrual.interestSoFar.formatted}',
              highlight: true,
            ),
            const Divider(height: 24),
            _EstRow(
              label: 'invest.atMaturity'.tr(),
              value: accrual.maturityValue.formatted,
              sub: '${'invest.totalInterest'.tr()}: ${accrual.totalInterest.formatted}',
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _EstRow extends StatelessWidget {
  const _EstRow({
    required this.label,
    required this.value,
    required this.sub,
    this.highlight = false,
  });
  final String label;
  final String value;
  final String sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: highlight ? scheme.primary : scheme.onSurface,
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
