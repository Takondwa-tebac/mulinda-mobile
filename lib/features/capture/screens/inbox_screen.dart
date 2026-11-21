import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../subscription/widgets/paywall_sheet.dart';
import '../data/inbox_repository.dart';
import '../data/sms_capability.dart';
import '../data/sms_manual_scanner.dart';

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
    bool possibleDuplicate = false,
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
          possibleDuplicate: possibleDuplicate,
          accounts: accounts,
          scrollController: scrollController,
          onApprove: (accountId, edits) async {
            if (isReceipt) {
              await repo.approveReceipt(
                id,
                financialAccountId: accountId,
                amount: edits.amount,
                merchant: edits.merchant,
              );
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

    _snack(
      result == 'approved' ? 'inbox.approved'.tr() : 'inbox.rejected'.tr(),
    );
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
    final empty =
        !loading && !hasError && smsList.isEmpty && receiptList.isEmpty;
    final errorMessage = sms.error?.toString() ?? receipts.error?.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('inbox.title'.tr()),
        actions: [
          if (SmsCapability.canReadSms) ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => context.pushNamed(Routes.manualSmsScan),
              tooltip: 'Manual SMS Scan',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                final result = await SmsManualScanner.instance.scanFinancialSms(manual: true);
                if (mounted) {
                  _snack(result.message);
                  ref.invalidate(pendingSmsProvider);
                  ref.invalidate(pendingReceiptsProvider);
                }
              },
            ),
          ],
        ],
      ),
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
                    const Text(
                      'Could not load inbox',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      errorMessage ?? 'Unknown error',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
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
                child: Text(
                  'inbox.empty'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (smsList.isNotEmpty) ...[
              _Header('inbox.messages'.tr()),
              ...smsList.map(
                (m) => _ItemCard(
                  icon: Icons.sms_outlined,
                  title: m.merchant ?? m.sender ?? 'inbox.messages'.tr(),
                  subtitle: m.amount != null ? 'MK ${m.amount}' : m.body,
                  onTap: () => _openReview(
                    id: m.id,
                    isReceipt: false,
                    parsed: m.parsed,
                    sender: m.sender,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (receiptList.isNotEmpty) ...[
              _Header('inbox.receipts'.tr()),
              ...receiptList.map(
                (r) => _ItemCard(
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
                    possibleDuplicate: r.duplicateTransactionId != null,
                  ),
                ),
              ),
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

/// The user's corrections to a scanned receipt before it is saved.
class ReceiptEdits {
  const ReceiptEdits({this.amount, this.merchant});

  final num? amount;
  final String? merchant;
}

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
    this.possibleDuplicate = false,
  });

  final bool isReceipt;
  final Map<String, dynamic>? parsed;
  final List<Account> accounts;
  final Future<void> Function(String accountId, ReceiptEdits edits) onApprove;
  final Future<void> Function() onReject;
  final ScrollController scrollController;
  final String? imageUrl;
  final String? sender;
  final bool possibleDuplicate;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  Account? _selectedAccount;
  bool _approving = false;
  bool _rejecting = false;
  String? _error;

  // A receipt's amount and merchant can be corrected before saving: what the
  // phone read may be incomplete (handwriting, a faded till slip).
  late final _amount = TextEditingController(text: _initialAmount);
  late final _merchant = TextEditingController(text: widget.parsed?['merchant']?.toString() ?? '');

  String get _initialAmount {
    final value = num.tryParse(widget.parsed?['amount']?.toString() ?? '');
    return value == null ? '' : value.toStringAsFixed(2);
  }

  bool get _busy => _approving || _rejecting;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_selectedAccount == null) {
      setState(() => _error = 'Please select an account');
      return;
    }
    final amount = num.tryParse(_amount.text.replaceAll(',', '').trim());
    if (widget.isReceipt && (amount == null || amount <= 0)) {
      setState(() => _error = 'inbox.amountRequired'.tr());
      return;
    }
    final merchant = _merchant.text.trim();
    setState(() {
      _approving = true;
      _error = null;
    });
    try {
      await widget.onApprove(
        _selectedAccount!.id,
        ReceiptEdits(amount: amount, merchant: merchant.isEmpty ? null : merchant),
      );
      if (mounted) Navigator.of(context).pop('approved');
    } on ApiException catch (e) {
      if (e.code == 'sms_capture_limit_reached') {
        if (mounted) {
          Navigator.of(context).pop();
          showPaywall(context, feature: 'SMS auto-capture');
        }
      } else if (mounted) {
        setState(() => _error = e.displayMessage);
      }
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

          if (widget.possibleDuplicate) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.content_copy_outlined, color: scheme.onErrorContainer, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'inbox.possibleDuplicate'.tr(),
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (widget.isReceipt) ...[
            TextField(
              controller: _merchant,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'inbox.merchant'.tr(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'inbox.amount'.tr(),
                prefixText: '$currency ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
          ],

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
                if (!widget.isReceipt && merchant != null) _DetailRow('Merchant', merchant),
                if (!widget.isReceipt && amount != null)
                  _DetailRow(
                    'Amount',
                    '$currency ${double.tryParse(amount.toString())?.toStringAsFixed(2) ?? amount}',
                  ),
                _DetailRow('Type', type[0].toUpperCase() + type.substring(1)),
                if (parsed['payee'] != null) _DetailRow('inbox.payee'.tr(), parsed['payee'].toString()),
                if (num.tryParse(parsed['fee']?.toString() ?? '') case final fee? when fee > 0)
                  _DetailRow('inbox.fee'.tr(), '$currency ${fee.toStringAsFixed(2)}'),
                if (widget.sender != null) _DetailRow('Sender', widget.sender!),
                if (parsed['reference'] != null)
                  _DetailRow('Reference', parsed['reference'].toString()),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Account selector
          Text(
            'Select Account',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),

          if (widget.accounts.isEmpty)
            Text(
              'No accounts found. Please add an account first.',
              style: TextStyle(color: scheme.error, fontSize: 13),
            )
          else
            InputDecorator(
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                errorText: _selectedAccount == null ? _error : null,
              ),
              child: DropdownButton<Account>(
                value: _selectedAccount,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                hint: const Text('Choose an account'),
                items: widget.accounts
                    .map(
                      (a) => DropdownMenuItem(
                        value: a,
                        child: Text(
                          a.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    )
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
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  child: _rejecting
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
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
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
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
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
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
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
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
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
