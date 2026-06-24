import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../activity/data/activity_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/inbox_repository.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final _busy = <String>{};

  Future<void> _act(String id, Future<void> Function() action, String okMessage) async {
    setState(() => _busy.add(id));
    try {
      await action();
      ref
        ..invalidate(pendingSmsProvider)
        ..invalidate(pendingReceiptsProvider)
        ..invalidate(transactionsProvider)
        ..invalidate(accountsProvider)
        ..invalidate(dashboardProvider);
      _snack(okMessage);
    } on ApiException catch (e) {
      _snack(e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final sms = ref.watch(pendingSmsProvider);
    final receipts = ref.watch(pendingReceiptsProvider);
    final repo = ref.read(inboxRepositoryProvider);

    final smsList = sms.valueOrNull ?? const [];
    final receiptList = receipts.valueOrNull ?? const [];
    final loading = sms.isLoading || receipts.isLoading;
    final hasError = !loading && (sms.hasError || receipts.hasError);
    final empty = !loading && !hasError && smsList.isEmpty && receiptList.isEmpty;
    final errorMessage = sms.error?.toString() ?? receipts.error?.toString();

    return Scaffold(
      appBar: AppBar(title: Text('inbox.title'.tr())),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pendingSmsProvider);
          ref.invalidate(pendingReceiptsProvider);
          await ref.read(pendingSmsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (loading) const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text('Could not load inbox',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(errorMessage ?? 'Unknown error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12)),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () {
                        ref.invalidate(pendingSmsProvider);
                        ref.invalidate(pendingReceiptsProvider);
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 64),
                child: Text('inbox.empty'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            if (smsList.isNotEmpty) ...[
              _Header('inbox.messages'.tr()),
              ...smsList.map((m) => _ReviewCard(
                    icon: Icons.sms_outlined,
                    title: m.merchant ?? m.sender ?? 'inbox.messages'.tr(),
                    subtitle: m.amount != null ? 'MK ${m.amount}' : m.body,
                    busy: _busy.contains(m.id),
                    onApprove: () => _act(m.id, () => repo.approveSms(m.id), 'inbox.approved'.tr()),
                    onReject: () => _act(m.id, () => repo.rejectSms(m.id), 'inbox.rejected'.tr()),
                  )),
              const SizedBox(height: 8),
            ],
            if (receiptList.isNotEmpty) ...[
              _Header('inbox.receipts'.tr()),
              ...receiptList.map((r) => _ReviewCard(
                    icon: Icons.receipt_long_outlined,
                    title: r.merchant ?? 'inbox.receipts'.tr(),
                    subtitle: r.amount != null ? 'MK ${r.amount}' : 'inbox.processing'.tr(),
                    busy: _busy.contains(r.id),
                    onApprove: () => _act(r.id, () => repo.approveReceipt(r.id), 'inbox.approved'.tr()),
                    onReject: () => _act(r.id, () => repo.rejectReceipt(r.id), 'inbox.rejected'.tr()),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(icon, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (busy)
              const Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onReject, child: Text('inbox.reject'.tr())),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: onApprove, child: Text('inbox.approve'.tr())),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
