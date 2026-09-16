import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/receipt_view.dart';
import '../../activity/data/activity_models.dart';
import '../data/summary_models.dart';
import '../data/summary_repository.dart';

/// Detailed breakdown of spending for a specific day with all transactions.
class DailySummaryDetailScreen extends ConsumerStatefulWidget {
  const DailySummaryDetailScreen({super.key, required this.summary});

  final DailySummary summary;

  @override
  ConsumerState<DailySummaryDetailScreen> createState() => _DailySummaryDetailScreenState();
}

class _DailySummaryDetailScreenState extends ConsumerState<DailySummaryDetailScreen> {
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
      final file = File('${dir.path}/mulinda_daily_${widget.summary.date}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: 'Mulinda daily summary for ${widget.summary.date}');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryDetail = ref.watch(dailySummaryDetailProvider(widget.summary.id));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_prettyDate(widget.summary.date)),
        actions: [
          if (_sharing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share summary',
              onPressed: _share,
            ),
        ],
      ),
      body: SafeArea(
        child: summaryDetail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Could not load summary details.')),
          data: (detail) {
            if (detail.transactions.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No transactions on this day'),
                  ],
                ),
              );
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
              children: [
                // Summary card
                RepaintBoundary(
                  key: _receiptKey,
                  child: ReceiptView(
                    title: 'Daily Summary',
                    subtitle: _prettyDate(detail.date),
                    amountLine: detail.net.formatted,
                    amountColor: detail.net.isNegative ? Colors.red.shade700 : Colors.green.shade700,
                    statusIcon: Icons.receipt_long,
                    statusColor: scheme.primary,
                    detailsHeading: 'Overview',
                    rows: [
                      ReceiptRow('Total spent', detail.expense.formatted, muted: true),
                      ReceiptRow('Total received', detail.income.formatted, muted: true),
                      ReceiptRow('Net change', detail.net.formatted, emphasize: true),
                      ReceiptRow('Transactions', '${detail.transactionCount}'),
                      if (detail.topCategory != null)
                        ReceiptRow('Top category', detail.topCategory!),
                      if (detail.topCategoryAmount != null)
                        ReceiptRow('Top amount', detail.topCategoryAmount!.formatted, muted: true),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Transactions list
                Text(
                  'Transactions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...detail.transactions.map((txn) => _TransactionTile(txn: txn)),
              ],
            );
          },
        ),
      ),
    );
  }

  String _prettyDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn});

  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: txn.isIncome ? Colors.green.shade100 : Colors.red.shade100,
          child: Icon(
            txn.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: txn.isIncome ? Colors.green.shade700 : Colors.red.shade700,
            size: 20,
          ),
        ),
        title: Text(
          txn.merchant ?? txn.counterparty ?? txn.categoryName ?? 'Transaction',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (txn.categoryName != null)
              Text(txn.categoryName!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              _prettyTime(txn.occurredAt),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${txn.isIncome ? '+' : '-'}${txn.amount.formatted}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: txn.isIncome ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            if (txn.children.isNotEmpty)
              Text(
                '+ fees',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  String _prettyTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
