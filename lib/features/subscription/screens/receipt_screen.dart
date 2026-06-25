import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/subscription_models.dart';

/// A shareable receipt for a paid (or comped) invoice. Mirrors the transaction
/// receipt: a RepaintBoundary rendered to a PNG and shared via share_plus.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.invoice});

  final InvoiceModel invoice;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _receiptKey = GlobalKey();
  bool _sharing = false;

  InvoiceModel get inv => widget.invoice;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mulinda_receipt_${inv.id}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${inv.periodLabel} · ${inv.amount.formatted}',
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
        title: Text('billReceipt.title'.tr()),
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
              tooltip: 'billReceipt.share'.tr(),
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
            child: _ReceiptCard(invoice: inv),
          ),
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.invoice});
  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final comped = invoice.status == 'comped';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(comped ? 'billReceipt.gift'.tr() : 'billReceipt.paid'.tr(),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer)),
                ),
              ],
            ),
            const SizedBox(height: 28),
            CircleAvatar(
              radius: 36,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.workspace_premium, size: 30),
            ),
            const SizedBox(height: 16),
            Text(invoice.amount.formatted,
                style: text.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: scheme.primary)),
            const SizedBox(height: 6),
            Text('${invoice.periodLabel} ${'billReceipt.subscription'.tr()}',
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 20),
            _Row('billReceipt.plan'.tr(), invoice.periodLabel),
            _Row('billReceipt.amount'.tr(), invoice.amount.formatted),
            if (invoice.provider != null)
              _Row('billReceipt.method'.tr(), _providerLabel(invoice.provider!)),
            if (invoice.paidAt != null)
              _Row('billReceipt.date'.tr(), _fmtDate(invoice.paidAt!)),
            _Row('billReceipt.reference'.tr(),
                '#${invoice.txRef.replaceAll('credit_', '').substring(0, 8).toUpperCase()}'),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Text('billReceipt.footer'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _providerLabel(String p) =>
      p == 'credit' ? 'billReceipt.gift'.tr() : p[0].toUpperCase() + p.substring(1);

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
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
            width: 110,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
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
