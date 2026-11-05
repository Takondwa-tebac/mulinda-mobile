import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/semantic_colors.dart';
import '../../../core/widgets/category_icons.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/receipt_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';
import '../../activity/widgets/category_picker.dart';
import '../../activity/widgets/category_quick_fix.dart';
import '../../activity/widgets/txn_view.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../../core/theme/app_icons.dart';

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
      await Share.shareXFiles([XFile(file.path)], text: 'activity2.detail.shareText'.tr());
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
    await ref
        .read(activityRepositoryProvider)
        .updateTransaction(
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('activity2.detail.updated'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(transactionDetailProvider(widget.txnId));

    return Scaffold(
      appBar: AppBar(
        title: Text('activity2.detail.title'.tr()),
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
                    tooltip: 'activity2.detail.edit'.tr(),
                    onPressed: () => _showEditSheet(txn),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'activity2.detail.share'.tr(),
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
        error: (_, _) => Center(
          child: ErrorRetry(
            message: 'activity2.detail.loadError'.tr(),
            onRetry: () => ref.invalidate(transactionDetailProvider(widget.txnId)),
          ),
        ),
        data: (txn) => ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 40 + MediaQuery.of(context).padding.bottom),
          children: [
            RepaintBoundary(
              key: _receiptKey,
              child: ReceiptView(
                title: _title(txn),
                subtitle: txn.merchant ?? txn.counterparty ?? txn.categoryName,
                amountLine: detailAmountLabel(txn),
                amountColor: txn.isIncome
                    ? context.semantic.income
                    : (txn.notSpending ? Theme.of(context).colorScheme.onSurfaceVariant : context.semantic.expense),
                statusColor: txn.isIncome ? context.semantic.success : Theme.of(context).colorScheme.primary,
                detailsHeading: 'activity2.detail.details'.tr(),
                rows: _rows(txn),
              ),
            ),
            if (txn.type != 'transfer') ...[
              const SizedBox(height: AppSpacing.lg),
              _CategoryCard(
                txn: txn,
                onChange: () => openCategoryQuickFix(context, ref, txn).then((saved) {
                  if (saved != null) {
                    ref
                      ..invalidate(transactionsProvider)
                      ..invalidate(accountsProvider);
                  }
                }),
              ),
            ],
            if (txn.sourceSms != null) ...[const SizedBox(height: 20), _SourceSmsCard(sms: txn.sourceSms!)],
          ],
        ),
      ),
    );
  }

  String _title(Txn txn) {
    if (txn.isIncome) return 'activity2.detail.received'.tr();
    return txn.type == 'transfer' ? 'activity2.detail.transfer'.tr() : 'activity2.detail.payment'.tr();
  }

  List<ReceiptRow> _rows(Txn txn) {
    final fee = txn.children.where((c) => c.isFee).firstOrNull;
    final levy = txn.children.where((c) => c.isLevy).firstOrNull;

    // Build amount breakdown string
    String amountText = detailAmountLabel(txn);
    if (fee != null || levy != null) {
      final parts = <String>[amountText];
      if (levy != null) parts.add('+ ${levy.amount.formatted} ${'activity2.detail.levyShort'.tr()}');
      if (fee != null) parts.add('+ ${fee.amount.formatted} ${'activity2.detail.feeShort'.tr()}');
      amountText = parts.join(' ');
    }

    return [
      if (txn.accountName != null) ReceiptRow('activity2.detail.from'.tr(), txn.accountName!),
      if ((txn.counterparty ?? txn.merchant) != null)
        ReceiptRow(
          txn.isIncome ? 'activity2.detail.fromParty'.tr() : 'activity2.detail.to'.tr(),
          (txn.counterparty ?? txn.merchant)!,
        ),
      ReceiptRow('activity2.detail.amount'.tr(), amountText, emphasize: true),
      // Show individual fee/levy breakdown for clarity
      if (fee != null) ReceiptRow('activity2.detail.fee'.tr(), '-${fee.amount.formatted}', muted: true),
      if (levy != null) ReceiptRow('activity2.detail.levy'.tr(), '-${levy.amount.formatted}', muted: true),
      if (txn.categoryName != null) ReceiptRow('activity2.detail.category'.tr(), txn.categoryName!),
      if (txn.reference != null) ReceiptRow('activity2.detail.reference'.tr(), txn.reference!),
      ReceiptRow('activity2.detail.date'.tr(), _prettyDateTime(txn.occurredAt)),
      if (txn.balanceAfter != null) ReceiptRow('activity2.detail.balanceAfter'.tr(), txn.balanceAfter!.formatted),
      if (txn.status != null)
        ReceiptRow('activity2.detail.status'.tr(), 'activity2.detail.statusValue.${txn.status}'.tr()),
      ReceiptRow(
        'activity2.detail.recordedVia'.tr(),
        txn.isAutoCaptured
            ? 'activity2.detail.viaSms'.tr()
            : (txn.source == 'scan' ? 'activity2.detail.viaScan'.tr() : 'activity2.detail.viaManual'.tr()),
      ),
      if (txn.notes != null && txn.notes!.isNotEmpty && txn.notes != txn.merchant)
        ReceiptRow('activity2.detail.note'.tr(), txn.notes!),
    ];
  }

  String _prettyDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${d.day} ${'common.monthShort.${d.month}'.tr()} ${d.year}, ${timeOfDay(d)}';
  }
}

/// Plain-language explanation of how a transaction got its category.
String categorisationExplanation(Txn txn) {
  final c = txn.categorisation;
  if (txn.categoryId == null) return 'activity2.detail.catSource.none'.tr();
  if (c == null) return 'activity2.detail.catSource.unknown'.tr();
  if (c.isSuggested) return 'activity2.detail.catSource.suggested'.tr();
  return switch (c.source) {
    'user' => 'activity2.detail.catSource.user'.tr(),
    'user_rule' => 'activity2.detail.catSource.userRule'.tr(),
    'merchant_rule' => 'activity2.detail.catSource.merchant'.tr(),
    'keyword' => 'activity2.detail.catSource.keyword'.tr(),
    'sms_kind' => 'activity2.detail.catSource.smsKind'.tr(),
    _ => 'activity2.detail.catSource.auto'.tr(),
  };
}

/// The category, how it was chosen, and a one-tap way to change it (no need
/// to open the whole edit sheet).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.txn, required this.onChange});

  final Txn txn;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needs = txn.needsCategory || txn.categoryId == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        // Info on top at full width, the action below it, so chips and the
        // explanation are not squeezed by a trailing button on narrow phones.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryAvatar(icon: txn.categoryIcon, color: txn.categoryColor, fallbackIcon: Icons.help_outline),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txn.categoryName ?? 'activity2.uncategorised'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        categorisationExplanation(txn),
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                      if (txn.notSpending) ...[
                        const SizedBox(height: AppSpacing.xs),
                        StatusChip(label: 'activity2.notSpending'.tr(), icon: Icons.swap_horiz),
                      ],
                      if (needs) ...[
                        const SizedBox(height: AppSpacing.xs),
                        StatusChip(
                          label: txn.categoryId == null
                              ? 'activity2.addCategory'.tr()
                              : 'activity2.confirmCategory'.tr(),
                          tone: StatusTone.warning,
                          icon: AppIcons.suggestion,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            needs
                ? FilledButton.tonal(
                    onPressed: onChange,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
                    child: Text(
                      txn.categoryId == null ? 'activity2.detail.choose'.tr() : 'activity2.detail.review'.tr(),
                    ),
                  )
                : OutlinedButton(
                    onPressed: onChange,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
                    child: Text('activity2.detail.change'.tr()),
                  ),
          ],
        ),
      ),
    );
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
          title: Text('activity2.detail.sourceSms'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            [sms.sender, sms.receivedAt?.replaceFirst('T', ' ').split('.').first].whereType<String>().join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(
                sms.body,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
              ),
            ),
            if (sms.parsed != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'activity2.detail.captured'.tr(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 6),
              ...sms.parsed!.entries
                  .where((e) => e.value != null && e.value.toString().isNotEmpty)
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(_label(e.key), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          ),
                          Expanded(
                            child: Text(
                              '${e.value}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
      await widget.onSave(
        _TxnEdit(
          type: _type == widget.txn.type ? null : _type,
          categoryId: _categoryId,
          merchant: _merchant.text.trim(),
          notes: _notes.text.trim(),
        ),
      );
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
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700);

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
                Text(
                  'activity2.detail.editTitle'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (_typeEditable) ...[
                        Text('activity2.detail.type'.tr(), style: labelStyle),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: 'income',
                              label: Text('activity2.detail.moneyIn'.tr()),
                              icon: const Icon(Icons.arrow_downward, size: 18),
                            ),
                            ButtonSegment(
                              value: 'expense',
                              label: Text('activity2.detail.expense'.tr()),
                              icon: const Icon(Icons.arrow_upward, size: 18),
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
                      Text('activity2.detail.category'.tr(), style: labelStyle),
                      const SizedBox(height: 8),
                      CategoryPickerField(
                        key: ValueKey('cat-$_type'),
                        value: _categoryId,
                        kind: _typeEditable ? _type : null,
                        createKind: _type,
                        enabled: !_saving,
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _merchant,
                        decoration: InputDecoration(labelText: 'activity2.detail.merchant'.tr()),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: InputDecoration(labelText: 'activity2.detail.notes'.tr()),
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
                                  'activity2.detail.smsLocked'.tr(),
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
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'activity2.detail.saving'.tr() : 'activity2.detail.save'.tr()),
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

/// The amount with its direction sign, matching the Activity list: income "+",
/// spending "-", and money moved between the user's own accounts (a
/// non-spending category) unsigned, because it is neither.
@visibleForTesting
String detailAmountLabel(Txn txn) {
  if (txn.notSpending) return txn.amount.formatted;
  return '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}';
}
