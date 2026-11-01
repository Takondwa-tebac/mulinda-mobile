import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/receipt_ocr.dart';

/// Debug-only tool: runs on-device OCR over sample receipt photos and shares
/// the results as `<image>.ocr.json` files, which become the receipt parser's
/// test fixtures. Only routed in debug builds, so its strings are not
/// localised.
class ReceiptOcrDebugScreen extends ConsumerStatefulWidget {
  const ReceiptOcrDebugScreen({super.key});

  @override
  ConsumerState<ReceiptOcrDebugScreen> createState() => _ReceiptOcrDebugScreenState();
}

class _OcrResult {
  const _OcrResult(this.name, this.file, this.document, this.millis);

  final String name;
  final File file;
  final OcrDocument document;
  final int millis;
}

class _ReceiptOcrDebugScreenState extends ConsumerState<ReceiptOcrDebugScreen> {
  final _picker = ImagePicker();
  final _results = <_OcrResult>[];
  bool _running = false;
  String? _error;

  Future<void> _pickAndRead() async {
    // Same compression as the real scan screen, so fixtures match what the
    // parser will see in production.
    final images = await _picker.pickMultiImage(imageQuality: 80);
    if (images.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
    });

    final ocr = ref.read(receiptOcrProvider);
    final outDir = Directory(p.join((await getTemporaryDirectory()).path, 'receipt-ocr'));
    await outDir.create(recursive: true);

    try {
      for (final image in images) {
        final watch = Stopwatch()..start();
        final doc = await ocr.read(image.path, source: image.name);
        watch.stop();

        final file = File(p.join(outDir.path, '${p.basenameWithoutExtension(image.name)}.ocr.json'));
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(doc.toJson()));

        if (!mounted) return;
        setState(() => _results.insert(0, _OcrResult(image.name, file, doc, watch.elapsedMilliseconds)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _shareAll() async {
    if (_results.isEmpty) return;
    await Share.shareXFiles(
      [for (final r in _results) XFile(r.file.path, mimeType: 'application/json')],
      text: 'Receipt OCR fixtures (${_results.length})',
    );
  }

  void _showText(_OcrResult result) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            result.document.text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt OCR (debug)'),
        actions: [
          IconButton(
            tooltip: 'Share JSON',
            onPressed: _results.isEmpty || _running ? null : _shareAll,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _running ? null : _pickAndRead,
        icon: _running
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Read receipts'),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [TextButton(onPressed: () => setState(() => _error = null), child: const Text('OK'))],
            ),
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Pick receipt photos to read them on the device, then share the JSON files.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      return ListTile(
                        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${r.document.lines.length} lines · ${r.millis} ms'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showText(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
