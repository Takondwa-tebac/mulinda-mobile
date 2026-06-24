import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../dashboard/data/dashboard_models.dart';

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.txn});

  final RecentTxn txn;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final _receiptKey = GlobalKey();
  bool _sharing = false;

  RecentTxn get txn => widget.txn;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mulinda_txn_${txn.id}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${txn.isIncome ? '+' : '-'}${txn.amount.formatted} · ${txn.date}',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (_sharing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: _share,
            ),
        ],
      ),
      backgroundColor: scheme.surfaceContainerLow,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: RepaintBoundary(
            key: _receiptKey,
            child: _ReceiptCard(txn: txn),
          ),
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.txn});
  final RecentTxn txn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isIncome = txn.isIncome;
    final amountColor = isIncome ? scheme.primary : scheme.error;

    final title = txn.merchant?.isNotEmpty == true
        ? txn.merchant!
        : (txn.category ?? txn.type);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App logo header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Image.asset('assets/logo.png', width: 28, height: 28),
                    const SizedBox(width: 8),
                    Text('Mulinda',
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isIncome
                        ? scheme.primaryContainer
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isIncome ? 'Income' : 'Expense',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isIncome
                            ? scheme.onPrimaryContainer
                            : scheme.onErrorContainer),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Icon
            CircleAvatar(
              radius: 36,
              backgroundColor:
                  isIncome ? scheme.primaryContainer : scheme.errorContainer,
              foregroundColor: isIncome
                  ? scheme.onPrimaryContainer
                  : scheme.onErrorContainer,
              child: Icon(
                  isIncome ? Icons.south_west : Icons.north_east, size: 30),
            ),
            const SizedBox(height: 16),

            // Amount
            Text(
              '${isIncome ? '+' : '-'}${txn.amount.formatted}',
              style: text.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800, color: amountColor),
            ),
            const SizedBox(height: 6),
            Text(title,
                textAlign: TextAlign.center,
                style: text.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),

            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 20),

            // Detail rows
            if (txn.category != null && txn.category != title)
              _Row('Category', txn.category!),
            _Row('Date', txn.date),
            _Row('Reference', '#${txn.id.substring(0, 8).toUpperCase()}'),

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Footer
            Text('Generated by Mulinda',
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
