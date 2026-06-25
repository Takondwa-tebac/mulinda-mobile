import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/subscription_models.dart';
import '../data/subscription_repository.dart';
import '../widgets/paywall_sheet.dart';
import 'checkout_webview_screen.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? _resuming;

  Future<void> _refresh() async {
    ref.invalidate(invoicesProvider);
    await ref.read(authControllerProvider.notifier).refresh();
    await ref.read(invoicesProvider(null).future);
  }

  /// Reopen checkout for a pending/failed invoice and re-verify on return.
  Future<void> _completePayment(InvoiceModel invoice) async {
    setState(() => _resuming = invoice.id);
    try {
      var checkoutUrl = invoice.checkoutUrl;

      // No stored URL (rare) — regenerate a fresh checkout for the same period.
      if (checkoutUrl == null) {
        final fresh =
            await ref.read(subscriptionRepositoryProvider).checkout(invoice.period);
        checkoutUrl = fresh.checkoutUrl;
      }
      if (checkoutUrl == null || !mounted) return;

      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CheckoutWebViewScreen(checkoutUrl: checkoutUrl!),
        ),
      );

      if (completed == true && mounted) {
        try {
          await ref.read(subscriptionRepositoryProvider).verify(invoice.id);
        } on ApiException catch (_) {
          // settled later by webhook/poller
        }
        await _refresh();
      }
    } on ApiException catch (e) {
      _snack(e.displayMessage, error: true);
    } finally {
      if (mounted) setState(() => _resuming = null);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(currentUserProvider)?.subscription ??
        const SubscriptionInfo.none();
    final invoicesAsync = ref.watch(invoicesProvider(null));

    return Scaffold(
      appBar: AppBar(title: Text('subscription.title'.tr())),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _StatusCard(sub: sub, onSubscribe: () => showPaywall(context)),
            const SizedBox(height: 24),
            Text('subscription.invoices'.tr(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            invoicesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorBlock(
                message: e is ApiException ? e.displayMessage : e.toString(),
                onRetry: () => ref.invalidate(invoicesProvider),
              ),
              data: (invoices) => invoices.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text('subscription.noInvoices'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    )
                  : Column(
                      children: invoices
                          .map((inv) => _InvoiceTile(
                                invoice: inv,
                                resuming: _resuming == inv.id,
                                onTap: () => _onInvoiceTap(inv),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _onInvoiceTap(InvoiceModel inv) {
    if (inv.isPaid) {
      context.push(Routes.receipt, extra: inv);
    } else if (inv.isResumable) {
      _completePayment(inv);
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sub, required this.onSubscribe});

  final SubscriptionInfo sub;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: sub.active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(sub.active ? Icons.verified : Icons.lock_open_outlined,
                    color: sub.active ? scheme.onPrimaryContainer : scheme.primary),
                const SizedBox(width: 10),
                Text(
                  sub.active
                      ? (sub.isTrial
                          ? 'subscription.trialActive'.tr()
                          : '${sub.planLabel ?? ''} · ${'subscription.active'.tr()}')
                      : 'subscription.free'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: sub.active
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sub.active && sub.endsAt != null
                  ? '${'subscription.renewsOrEnds'.tr()} ${_fmtDate(sub.endsAt!)}'
                  : 'subscription.freeBlurb'.tr(),
              style: TextStyle(
                color: sub.active
                    ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                    : scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSubscribe,
                icon: const Icon(Icons.workspace_premium),
                label: Text(sub.active
                    ? 'subscription.extend'.tr()
                    : 'subscription.subscribe'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({
    required this.invoice,
    required this.resuming,
    required this.onTap,
  });

  final InvoiceModel invoice;
  final bool resuming;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label, icon) = _statusVisual(context, invoice.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: (invoice.isPaid || invoice.isResumable) && !resuming ? onTap : null,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Icon(icon, size: 18),
        ),
        title: Text('${invoice.periodLabel} · ${invoice.amount.formatted}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          invoice.createdAt != null ? _fmtDate(invoice.createdAt!) : label,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        trailing: resuming
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5))
            : invoice.isResumable
                ? TextButton(
                    onPressed: onTap, child: Text('subscription.complete'.tr()))
                : invoice.isPaid
                    ? Icon(Icons.receipt_long_outlined,
                        color: scheme.onSurfaceVariant)
                    : _Chip(label: label, color: color),
      ),
    );
  }

  (Color, String, IconData) _statusVisual(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      'paid' => (scheme.primary, 'subscription.statusPaid'.tr(), Icons.check_circle),
      'comped' => (scheme.tertiary, 'subscription.statusGift'.tr(), Icons.card_giftcard),
      'pending' => (Colors.orange, 'subscription.statusPending'.tr(), Icons.schedule),
      'failed' => (scheme.error, 'subscription.statusFailed'.tr(), Icons.error_outline),
      'cancelled' => (scheme.onSurfaceVariant, 'subscription.statusCancelled'.tr(), Icons.cancel_outlined),
      _ => (scheme.onSurfaceVariant, status, Icons.receipt_long_outlined),
    };
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_outlined, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text('common.retry'.tr())),
        ],
      ),
    );
  }
}
