import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/inbox_repository.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  Future<void> _openReview({
    required String id,
    required bool isReceipt,
    required Map<String, dynamic>? parsed,
    String? imageUrl,
    String? sender,
  }) async {
    final repo = ref.read(inboxRepositoryProvider);
    final accounts = await ref
        .read(accountsProvider.future)
        .catchError((_) => <Account>[]);

    if (!mounted) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 1.0,
        builder: (_, scrollController) => _ReviewSheet(
          isReceipt: isReceipt,
          parsed: parsed,
          imageUrl: imageUrl,
          sender: sender,
          accounts: accounts,
          scrollController: scrollController,
          onApprove: (accountId) async {
            if (isReceipt) {
              await repo.approveReceipt(id, financialAccountId: accountId);
            } else {
              await repo.approveSms(id, financialAccountId: accountId);
            }
          },
          onReject: () async {
            if (isReceipt) {
              await repo.rejectReceipt(id);
            } else {
              await repo.rejectSms(id);
            }
          },
        ),
      ),
    );

    if (!mounted || result == null) return;

    ref
      ..invalidate(pendingSmsProvider)
      ..invalidate(pendingReceiptsProvider)
      ..invalidate(transactionsProvider)
      ..invalidate(accountsProvider)
      ..invalidate(dashboardProvider);

    _snack(result == 'approved' ? 'inbox.approved'.tr() : 'inbox.rejected'.tr());
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
            if (loading)
              const Padding(
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
                    const Text('Could not load inbox',
                        style: TextStyle(fontWeight: FontWeight.w600)),
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
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            if (smsList.isNotEmpty) ...[
              _Header('inbox.messages'.tr()),
              ...smsList.map((m) => _ItemCard(
                    icon: Icons.sms_outlined,
                    title: m.merchant ?? m.sender ?? 'inbox.messages'.tr(),
                    subtitle: m.amount != null ? 'MK ${m.amount}' : m.body,
                    onTap: () => _openReview(
                      id: m.id,
                      isReceipt: false,
                      parsed: m.parsed,
                      sender: m.sender,
                    ),
                  )),
              const SizedBox(height: 8),
            ],
            if (receiptList.isNotEmpty) ...[
              _Header('inbox.receipts'.tr()),
              ...receiptList.map((r) => _ItemCard(
                    icon: Icons.receipt_long_outlined,
                    title: r.merchant ?? 'inbox.receipts'.tr(),
                    subtitle: r.amount != null
                        ? 'MK ${r.amount}'
                        : 'inbox.processing'.tr(),
                    onTap: () => _openReview(
                      id: r.id,
                      isReceipt: true,
                      parsed: r.parsed,
                      imageUrl: r.imageUrl,
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review bottom sheet
// ---------------------------------------------------------------------------

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.isReceipt,
    required this.parsed,
    required this.accounts,
    required this.onApprove,
    required this.onReject,
    required this.scrollController,
    this.imageUrl,
    this.sender,
  });

  final bool isReceipt;
  final Map<String, dynamic>? parsed;
  final List<Account> accounts;
  final Future<void> Function(String accountId) onApprove;
  final Future<void> Function() onReject;
  final ScrollController scrollController;
  final String? imageUrl;
  final String? sender;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  Account? _selectedAccount;
  bool _approving = false;
  bool _rejecting = false;
  String? _error;

  bool get _busy => _approving || _rejecting;

  Future<void> _approve() async {
    if (_selectedAccount == null) {
      setState(() => _error = 'Please select an account');
      return;
    }
    setState(() {
      _approving = true;
      _error = null;
    });
    try {
      await widget.onApprove(_selectedAccount!.id);
      if (mounted) Navigator.of(context).pop('approved');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _rejecting = true);
    try {
      await widget.onReject();
      if (mounted) Navigator.of(context).pop('rejected');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = widget.parsed ?? {};
    final merchant = parsed['merchant']?.toString();
    final amount = parsed['amount'];
    final currency = parsed['currency']?.toString() ?? 'MWK';
    final type = parsed['type']?.toString() ?? 'expense';

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        32 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              widget.isReceipt ? 'Review Receipt' : 'Review SMS',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),

            // Extracted details card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (merchant != null) _DetailRow('Merchant', merchant),
                  if (amount != null)
                    _DetailRow(
                      'Amount',
                      '$currency ${double.tryParse(amount.toString())?.toStringAsFixed(2) ?? amount}',
                    ),
                  _DetailRow('Type', type[0].toUpperCase() + type.substring(1)),
                  if (widget.sender != null) _DetailRow('Sender', widget.sender!),
                  if (parsed['reference'] != null)
                    _DetailRow('Reference', parsed['reference'].toString()),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Account selector
            Text('Select Account',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),

            if (widget.accounts.isEmpty)
              Text('No accounts found. Please add an account first.',
                  style: TextStyle(color: scheme.error, fontSize: 13))
            else
              InputDecorator(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  errorText: _selectedAccount == null ? _error : null,
                ),
                child: DropdownButton<Account>(
                  value: _selectedAccount,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: const Text('Choose an account'),
                  items: widget.accounts
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child: Text(a.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedAccount = v;
                    _error = null;
                  }),
                ),
              ),

            if (_error != null && _selectedAccount != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
            ],

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.error),
                    ),
                    child: _rejecting
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Theme.of(context).colorScheme.error))
                        : const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy || widget.accounts.isEmpty ? null : _approve,
                    child: _approving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Approve & Save'),
                  ),
                ),
              ],
            ),
          ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
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
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
