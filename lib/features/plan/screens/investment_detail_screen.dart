import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/currencies.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/investment_types.dart';
import '../widgets/mse_logo.dart';
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
                    Row(
                      children: [
                        if (inv.type == 'shares') ...[
                          MseLogo(ticker: inv.ticker, name: inv.name, size: 34),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            'invest.type.${inv.type}'.tr(),
                            style: TextStyle(
                              color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
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

            if (inv.type == 'shares') _SharePriceCard(investment: inv),

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
            _DetailsCard(investment: inv),
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

/// A share's price today, how it moved since the last price entered, and the gain
/// or loss that is on the units held. The price is entered by hand (the exchange
/// has no open data feed), so the card says when it was last updated.
class _SharePriceCard extends ConsumerWidget {
  const _SharePriceCard({required this.investment});

  final InvestmentItem investment;

  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PriceSheet(investment: investment),
    );
    if (saved == true) {
      ref.invalidate(investmentsListProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final trade = investment.lastTrade;
    final up = trade?.isUp ?? false;
    final down = trade?.isDown ?? false;
    final color = up ? Colors.green.shade700 : (down ? scheme.error : scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('investForm.priceTitle'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _update(context, ref),
                    child: Text('investForm.updatePrice'.tr()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (trade == null)
                Text('investForm.noPriceYet'.tr(), style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35))
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(trade.price.formatted, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(trade.pricedOn, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (trade.hasChange && trade.changePercent != null)
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${up ? '▲' : (down ? '▼' : '')} ${(trade.changePercent!.abs() * 100).toStringAsFixed(2)}%',
                        style: TextStyle(color: color, fontWeight: FontWeight.w800),
                      ),
                      if (trade.dayGain != null)
                        Text(
                          '${'investForm.gainToday'.tr()}: ${trade.dayGain!.formatted}',
                          style: TextStyle(color: color, fontWeight: FontWeight.w600),
                        ),
                    ],
                  )
                else
                  Text('investForm.needSecondPrice'.tr(), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceSheet extends ConsumerStatefulWidget {
  const _PriceSheet({required this.investment});

  final InvestmentItem investment;

  @override
  ConsumerState<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends ConsumerState<_PriceSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _price = TextEditingController(
    text: widget.investment.lastTrade == null ? '' : widget.investment.lastTrade!.price.amount.toString(),
  );
  DateTime _day = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(planRepositoryProvider).recordSharePrice(
            widget.investment.id,
            double.parse(_price.text.trim()),
            day: _day,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('investForm.priceSaved'.tr())));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('investForm.updatePrice'.tr(), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('investForm.priceHint'.tr(), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.35)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'investForm.pricePerShare'.tr()),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                return (n == null || n <= 0) ? 'auth.required'.tr() : null;
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _day = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(labelText: 'investForm.priceDate'.tr()),
                child: Text(_day.toIso8601String().split('T').first),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('form.save'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The facts specific to this kind of holding (a share's units and price, a
/// SACCO's member number...), labelled from the server's description of the type.
class _DetailsCard extends ConsumerWidget {
  const _DetailsCard({required this.investment});

  final InvestmentItem investment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (investment.details.isEmpty) return const SizedBox.shrink();
    final lang = context.locale.languageCode;
    final defs = ref.watch(investmentTypesProvider).valueOrNull ?? fallbackInvestmentTypes;
    final def = defs.where((d) => d.type == investment.type).firstOrNull;
    if (def == null) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (final f in def.fields) {
      final raw = investment.details[f.key];
      if (raw == null || raw.toString().isEmpty) continue;
      rows.add(_InfoRow(icon: Icons.notes_outlined, label: f.label(lang), value: _show(f, raw, lang)));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(child: Column(children: rows)),
    );
  }

  String _show(InvestmentField f, Object raw, String lang) {
    switch (f.kind) {
      case 'money':
        final v = (raw as num).toDouble();
        final whole = v == v.roundToDouble();
        final parts = v.toStringAsFixed(whole ? 0 : 2).split('.');
        final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
        final symbol = currencyInfo(investment.amountInvested.currency).symbol;
        return parts.length > 1 ? '$symbol $grouped.${parts[1]}' : '$symbol $grouped';
      case 'percent':
        return '$raw%';
      case 'select':
        return f.options.where((o) => o.value == raw).firstOrNull?.label(lang) ?? raw.toString();
      case 'number':
        final v = (raw as num).toDouble();
        return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
      default:
        return raw.toString();
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
