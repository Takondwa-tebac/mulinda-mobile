import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/receipt_view.dart';
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        child: RepaintBoundary(
          key: _receiptKey,
          child: _buildReceipt(context),
        ),
      ),
    );
  }

  Widget _buildReceipt(BuildContext context) {
    final comped = inv.status == 'comped';
    return ReceiptView(
      title: comped ? 'billReceipt.gift'.tr() : 'billReceipt.paid'.tr(),
      subtitle: '${inv.periodLabel} ${'billReceipt.subscription'.tr()}',
      amountLine: inv.amount.formatted,
      detailsHeading: 'billReceipt.title'.tr(),
      footer: 'billReceipt.footer'.tr(),
      rows: [
        ReceiptRow('billReceipt.plan'.tr(), inv.periodLabel),
        ReceiptRow('billReceipt.amount'.tr(), inv.amount.formatted, emphasize: true),
        if (inv.provider != null) ReceiptRow('billReceipt.method'.tr(), _providerLabel(inv.provider!)),
        if (inv.paidAt != null) ReceiptRow('billReceipt.date'.tr(), _fmtDate(inv.paidAt!)),
        ReceiptRow('billReceipt.reference'.tr(),
            '#${inv.txRef.replaceAll('credit_', '').substring(0, 8).toUpperCase()}'),
      ],
    );
  }

  String _providerLabel(String p) =>
      p == 'credit' ? 'billReceipt.gift'.tr() : p[0].toUpperCase() + p.substring(1);

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
