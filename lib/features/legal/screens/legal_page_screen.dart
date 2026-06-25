import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/network/dio_client.dart';

/// Fetches a content page (privacy/terms) from the API and renders its HTML in
/// a webview, themed to match the app.
class LegalPageScreen extends ConsumerStatefulWidget {
  const LegalPageScreen({super.key, required this.slug});

  final String slug; // 'privacy' | 'terms'

  @override
  ConsumerState<LegalPageScreen> createState() => _LegalPageScreenState();
}

class _LegalPageScreenState extends ConsumerState<LegalPageScreen> {
  final _controller = WebViewController()..setJavaScriptMode(JavaScriptMode.disabled);
  String _title = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).get('/v1/pages/${widget.slug}');
      final data = (res.data['data'] as Map).cast<String, dynamic>();
      _title = data['title']?.toString() ?? '';
      await _controller.loadHtmlString(_wrap(data['html']?.toString() ?? ''));
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'legal.loadError'.tr();
        });
      }
    }
  }

  /// Wrap raw HTML in a minimal responsive, readable document.
  String _wrap(String html) {
    final scheme = Theme.of(context).colorScheme;
    String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return '''
<!DOCTYPE html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font-family: -apple-system, Roboto, sans-serif; margin: 16px; line-height: 1.55;
         color: ${hex(scheme.onSurface)}; background: ${hex(scheme.surface)}; }
  h1 { font-size: 1.5rem; } h2 { font-size: 1.15rem; margin-top: 1.4em; }
  a { color: ${hex(scheme.primary)}; }
  strong { font-weight: 600; }
  ul { padding-left: 1.2em; }
  em { color: ${hex(scheme.onSurfaceVariant)}; }
</style></head><body>$html</body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title.isEmpty ? 'legal.title'.tr() : _title)),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: Text('common.retry'.tr())),
                ],
              ),
            )
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
