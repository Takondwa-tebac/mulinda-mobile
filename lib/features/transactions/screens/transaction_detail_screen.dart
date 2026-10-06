import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/receipt_view.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';

/// Robust transaction detail: a share-ready receipt (bank-style), the fee/levy
/// breakdown, and — for auto-captured transactions — the exact source SMS.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.txnId});

  final String txnId;

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends ConsumerState<TransactionDetailScreen> {
  final _receiptKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mulinda_receipt_${widget.txnId}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: 'Mulinda transaction receipt');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showEditSheet(Txn txn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditTransactionSheet(txn: txn, onSave: _saveEdit),
    );
  }

  /// Throws [ApiException] on failure so the sheet can show the error and stay
  /// open; on success the sheet closes itself.
  Future<void> _saveEdit(_TxnEdit edit) async {
    await ref.read(activityRepositoryProvider).updateTransaction(
      widget.txnId,
      type: edit.type,
      categoryId: edit.categoryId,
      merchant: edit.merchant,
      notes: edit.notes,
    );
    // A type change moves money between income/expense, so refresh everything
    // that shows balances or totals.
    ref
      ..invalidate(transactionDetailProvider(widget.txnId))
      ..invalidate(transactionsProvider)
      ..invalidate(accountsProvider)
      ..invalidate(dashboardProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(transactionDetailProvider(widget.txnId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (_sharing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else
            detail.maybeWhen(
              data: (txn) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit transaction',
                    onPressed: () => _showEditSheet(txn),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Share receipt',
                    onPressed: _share,
                  ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load this transaction.')),
        data: (txn) => ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 40 + MediaQuery.of(context).padding.bottom),
          children: [
            RepaintBoundary(
              key: _receiptKey,
              child: ReceiptView(
                title: _title(txn),
                subtitle: txn.merchant ?? txn.counterparty ?? txn.categoryName,
                amountLine: '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}',
                amountColor: txn.isIncome ? Colors.green.shade700 : Colors.red.shade700,
                statusColor: txn.isIncome ? Colors.green.shade600 : Theme.of(context).colorScheme.primary,
                detailsHeading: 'Transaction Details',
                rows: _rows(txn),
              ),
            ),
            if (txn.sourceSms != null) ...[
              const SizedBox(height: 20),
              _SourceSmsCard(sms: txn.sourceSms!),
            ],
          ],
        ),
      ),
    );
  }

  String _title(Txn txn) {
    if (txn.isIncome) return 'Money Received';
    return txn.type == 'transfer' ? 'Transfer' : 'Payment';
  }

  List<ReceiptRow> _rows(Txn txn) {
    final fee = txn.children.where((c) => c.isFee).firstOrNull;
    final levy = txn.children.where((c) => c.isLevy).firstOrNull;

    // Build amount breakdown string
    String amountText = '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}';
    if (fee != null || levy != null) {
      final parts = <String>[amountText];
      if (levy != null) parts.add('+ ${levy.amount.formatted} levy');
      if (fee != null) parts.add('+ ${fee.amount.formatted} fee');
      amountText = parts.join(' ');
    }

    return [
      if (txn.accountName != null) ReceiptRow('From', txn.accountName!),
      if ((txn.counterparty ?? txn.merchant) != null)
        ReceiptRow(txn.isIncome ? 'From party' : 'To', (txn.counterparty ?? txn.merchant)!),
      ReceiptRow('Amount', amountText, emphasize: true),
      // Show individual fee/levy breakdown for clarity
      if (fee != null) ReceiptRow('Transaction fee', '-${fee.amount.formatted}', muted: true),
      if (levy != null) ReceiptRow('Government levy (0.05%)', '-${levy.amount.formatted}', muted: true),
      if (txn.categoryName != null) ReceiptRow('Category', txn.categoryName!),
      if (txn.reference != null) ReceiptRow('Reference', txn.reference!),
      ReceiptRow('Date', _prettyDateTime(txn.occurredAt)),
      if (txn.balanceAfter != null) ReceiptRow('Balance after', txn.balanceAfter!.formatted),
      if (txn.status != null) ReceiptRow('Status', _cap(txn.status!)),
      ReceiptRow('Recorded via', txn.isAutoCaptured ? 'SMS auto-capture' : 'Manual entry'),
      if (txn.notes != null && txn.notes!.isNotEmpty && txn.notes != txn.merchant)
        ReceiptRow('Note', txn.notes!),
    ];
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _prettyDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
  }
}

/// Collapsible card showing the exact SMS the transaction was parsed from.
class _SourceSmsCard extends StatelessWidget {
  const _SourceSmsCard({required this.sms});
  final SourceSms sms;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.sms_outlined),
          title: const Text('Source SMS', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            [sms.sender, sms.receivedAt?.replaceFirst('T', ' ').split('.').first]
                .whereType<String>()
                .join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                sms.body,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
              ),
            ),
            if (sms.parsed != null) ...[
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('What we captured',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
              ),
              const SizedBox(height: 6),
              ...sms.parsed!.entries
                  .where((e) => e.value != null && e.value.toString().isNotEmpty)
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(_label(e.key),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                            Expanded(
                              child: Text('${e.value}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      )),
            ],
          ],
        ),
      ),
    );
  }

  String _label(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

/// The values chosen in the edit sheet.
class _TxnEdit {
  const _TxnEdit({this.type, this.categoryId, required this.merchant, required this.notes});

  /// Null when the type is unchanged.
  final String? type;
  final String? categoryId;
  final String merchant;
  final String notes;
}

/// Bottom sheet for editing a transaction: type (money in / expense), category,
/// merchant and notes. The source SMS is never editable, to keep data integrity.
class _EditTransactionSheet extends ConsumerStatefulWidget {
  const _EditTransactionSheet({required this.txn, required this.onSave});

  final Txn txn;
  final Future<void> Function(_TxnEdit) onSave;

  @override
  ConsumerState<_EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends ConsumerState<_EditTransactionSheet> {
  late final TextEditingController _merchant;
  late final TextEditingController _notes;
  late String _type;
  String? _categoryId;
  bool _saving = false;

  /// Transfers keep their type: they need a counterpart account to be valid.
  bool get _typeEditable => widget.txn.type != 'transfer';

  @override
  void initState() {
    super.initState();
    _merchant = TextEditingController(text: widget.txn.merchant ?? '');
    _notes = TextEditingController(text: widget.txn.notes ?? '');
    _type = widget.txn.type;
    _categoryId = widget.txn.categoryId;
  }

  @override
  void dispose() {
    _merchant.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_TxnEdit(
        type: _type == widget.txn.type ? null : _type,
        categoryId: _categoryId,
        merchant: _merchant.text.trim(),
        notes: _notes.text.trim(),
      ));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit Transaction',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (_typeEditable) ...[
                        Text('Type', style: labelStyle),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'income',
                              label: Text('Money in'),
                              icon: Icon(Icons.arrow_downward, size: 18),
                            ),
                            ButtonSegment(
                              value: 'expense',
                              label: Text('Expense'),
                              icon: Icon(Icons.arrow_upward, size: 18),
                            ),
                          ],
                          selected: {_type},
                          onSelectionChanged: _saving
                              ? null
                              : (s) => setState(() {
                                    _type = s.first;
                                    // A category only fits its own kind.
                                    _categoryId = null;
                                  }),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text('Category', style: labelStyle),
                      const SizedBox(height: 8),
                      categories.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const Text('Failed to load categories'),
                        data: (cats) {
                          final options =
                              _typeEditable ? cats.where((c) => c.kind == _type).toList() : cats;
                          final selected =
                              options.any((c) => c.id == _categoryId) ? _categoryId : null;
                          return DropdownButtonFormField<String?>(
                            key: ValueKey('cat-$_type'),
                            initialValue: selected,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('None')),
                              ...options.map((c) => DropdownMenuItem<String?>(
                                    value: c.id,
                                    child: Text(c.name),
                                  )),
                            ],
                            onChanged: _saving ? null : (v) => setState(() => _categoryId = v),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _merchant,
                        decoration: const InputDecoration(
                          labelText: 'Merchant / Payee',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (widget.txn.isAutoCaptured)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: scheme.onErrorContainer),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Source SMS cannot be edited to maintain data integrity.',
                                  style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Saving...' : 'Save Changes'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
