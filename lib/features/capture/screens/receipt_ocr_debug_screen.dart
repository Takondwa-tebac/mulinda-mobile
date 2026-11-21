import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/receipt_capture.dart';
import '../data/receipt_ocr.dart';
import '../data/receipt_parser.dart';

const _parser = ReceiptParser();

/// One-line summary of what the parser made of a receipt.
String _describe(ReceiptDraft d) => [
      d.kind.name,
      d.amount?.toStringAsFixed(2) ?? 'no amount',
      if (d.merchant != null) d.merchant!,
      '${(d.confidence * 100).round()}%',
      if (d.needsFallback) '→ AI fallback',
    ].join(' · ');

/// Debug-only tool: runs on-device OCR over sample receipt photos and shares
/// each one as a matching pair, `receipt_<time>_<n>.jpg` (the photo exactly
/// as the parser saw it) and `receipt_<time>_<n>.ocr.json`, which become the
/// receipt parser's test fixtures. Only routed in debug builds, so its
/// strings are not localised.
class ReceiptOcrDebugScreen extends ConsumerStatefulWidget {
  const ReceiptOcrDebugScreen({super.key});

  @override
  ConsumerState<ReceiptOcrDebugScreen> createState() => _ReceiptOcrDebugScreenState();
}

class _OcrResult {
  const _OcrResult(this.name, this.image, this.file, this.document, this.millis);

  /// The pair's shared name, without extension.
  final String name;
  final File image;
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
    await _read([for (final i in images) i.path], prefix: 'receipt');
  }

  /// One receipt through the document scanner, exactly as the scan screen
  /// takes it (cropped and straightened), named `scan_<time>_01`.
  Future<void> _scanAndRead() async {
    try {
      final path = await ReceiptCapture(ref.read(receiptCaptureDeviceProvider)).fromCamera();
      if (path != null) await _read([path], prefix: 'scan');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _read(List<String> images, {required String prefix}) async {
    setState(() {
      _running = true;
      _error = null;
    });

    final ocr = ref.read(receiptOcrProvider);
    final outDir = Directory(p.join((await getTemporaryDirectory()).path, 'receipt-ocr'));
    await outDir.create(recursive: true);

    // The picker's own file names (scaled_1000785244.jpg) don't match the
    // gallery, so each photo and its OCR share a name of our own instead.
    final batch = _timestamp(DateTime.now());

    try {
      for (final (i, image) in images.indexed) {
        final name = '${prefix}_${batch}_${(i + 1).toString().padLeft(2, '0')}';
        final ext = p.extension(image).isEmpty ? '.jpg' : p.extension(image).toLowerCase();
        final photo = await File(image).copy(p.join(outDir.path, '$name$ext'));

        final watch = Stopwatch()..start();
        final doc = await ocr.read(photo.path, source: '$name$ext');
        watch.stop();

        // The parser's reading rides along to pre-fill the expected answers;
        // the fixture tool keeps only the OCR lines.
        final file = File(p.join(outDir.path, '$name.ocr.json'));
        await file.writeAsString(const JsonEncoder.withIndent('  ')
            .convert({...doc.toJson(), 'draft': _parser.parse(doc).toPayload()}));

        if (!mounted) return;
        setState(() => _results.insert(0, _OcrResult(name, photo, file, doc, watch.elapsedMilliseconds)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  Future<void> _shareAll() async {
    if (_results.isEmpty) return;
    await Share.shareXFiles(
      [
        for (final r in _results.reversed) ...[
          XFile(r.image.path),
          XFile(r.file.path, mimeType: 'application/json'),
        ],
      ],
      text: 'Receipt OCR fixtures (${_results.length} photos + JSON)',
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
            tooltip: 'Scan with camera',
            onPressed: _running ? null : _scanAndRead,
            icon: const Icon(Icons.document_scanner_outlined),
          ),
          IconButton(
            tooltip: 'Share photos + JSON',
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
                        'Pick receipt photos to read them on the device, then share them: '
                        'each photo comes with a matching .ocr.json.',
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
                        subtitle: Text('${r.document.lines.length} lines · ${r.millis} ms\n${_describe(_parser.parse(r.document))}'),
                        isThreeLine: true,
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
