import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_date_field.dart';
import '../../subscription/screens/checkout_webview_screen.dart';
import '../data/export_models.dart';
import '../data/export_repository.dart';

/// Export your financial records to CSV or PDF. Free with a paid or gifted
/// subscription; otherwise (including on the free trial) a one-time K50 (paid via PayChangu).
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String _format = 'csv';
  DateTime? _from;
  DateTime? _to;
  bool _busy = false;
  String? _statusLine;

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusLine = 'Preparing your export…';
    });
    final repo = ref.read(exportRepositoryProvider);
    try {
      var export = await repo.request(
        format: _format,
        from: _from,
        to: _to,
      );

      // Non-subscriber: take payment first.
      if (export.needsPayment) {
        final settled = await _payAndVerify(export);
        if (settled == null) {
          setState(() => _statusLine = null);
          return; // user cancelled or payment still pending
        }
        export = settled;
      }

      if (export.isReady) {
        await _deliver(export);
      } else if (export.isFailed) {
        _snack(export.failureReason ?? 'Export failed. Please try again.');
      } else {
        _snack('Your export is being prepared — check back shortly.');
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusLine = null;
        });
      }
    }
  }

  /// Open the hosted checkout, then verify (with a short poll) once it closes.
  Future<ExportModel?> _payAndVerify(ExportModel export) async {
    final url = export.checkoutUrl;
    if (url == null) return null;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('One-time export'),
        content: Text(
          'Exporting your records is ${export.amount?.formatted ?? 'K50'} as a one-time '
          'payment — or free with any active Mulinda subscription.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Pay & export')),
        ],
      ),
    );
    if (proceed != true || !mounted) return null;

    final returned = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CheckoutWebViewScreen(checkoutUrl: url)),
    );
    if (returned != true) return null;

    setState(() => _statusLine = 'Confirming payment…');
    final repo = ref.read(exportRepositoryProvider);
    // Poll a few times — settlement is verified server-side and may lag the redirect.
    for (var attempt = 0; attempt < 5; attempt++) {
      final verified = await repo.verify(export.id);
      if (verified.isReady) return verified;
      if (verified.isFailed) return verified;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    _snack('Payment is still processing. Your export will appear once it clears.');
    return null;
  }

  Future<void> _deliver(ExportModel export) async {
    setState(() => _statusLine = 'Downloading…');
    final file = await ref.read(exportRepositoryProvider).download(export);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'My Mulinda financial records',
    );
    if (mounted) _snack('Export ready — ${export.rowCount ?? ''} records.');
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export records')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Format', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'csv', label: Text('CSV'), icon: Icon(Icons.table_chart_outlined)),
              ButtonSegment(value: 'pdf', label: Text('PDF'), icon: Icon(Icons.picture_as_pdf_outlined)),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 24),
          const Text('Date range (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppDateField(
                  label: 'common.from'.tr(),
                  value: _from,
                  lastDate: _to ?? DateTime.now(),
                  clearable: true,
                  onChanged: (d) => setState(() => _from = d),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppDateField(
                  label: 'common.to'.tr(),
                  value: _to,
                  firstDate: _from ?? DateTime(2015),
                  lastDate: DateTime.now(),
                  clearable: true,
                  onChanged: (d) => setState(() => _to = d),
                ),
              ),
            ],
          ),
          if (_from != null || _to != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
                child: const Text('Clear dates'),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Free with a paid subscription. Otherwise, including during the free trial, a one-time K50 covers this export.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_busy ? (_statusLine ?? 'Working…') : 'Export & share'),
          ),
          if (_statusLine != null && _busy)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_statusLine!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}
