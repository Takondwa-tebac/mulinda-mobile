import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/receipt_view.dart';
import '../../activity/data/activity_models.dart';
import '../../activity/data/activity_repository.dart';

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
              data: (_) => IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share receipt',
                onPressed: _share,
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
    return [
      if (txn.accountName != null) ReceiptRow('From', txn.accountName!),
      if ((txn.counterparty ?? txn.merchant) != null)
        ReceiptRow(txn.isIncome ? 'From party' : 'To', (txn.counterparty ?? txn.merchant)!),
      ReceiptRow('Amount', '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}', emphasize: true),
      // Fee / levy breakdown, if this principal was split.
      for (final c in txn.children)
        ReceiptRow(c.isLevy ? 'Govt levy' : 'Fee', '-${c.amount.formatted}', muted: true),
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
