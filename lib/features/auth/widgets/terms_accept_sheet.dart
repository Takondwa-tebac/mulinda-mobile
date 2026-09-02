import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/network/dio_client.dart';

/// Full-screen Terms sheet whose "I have read & agree" button only enables once
/// the user has scrolled to the end — so acceptance is informed, not reflexive.
/// Returns true when accepted.
Future<bool?> showTermsAcceptSheet(BuildContext context, {String slug = 'terms'}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => TermsAcceptSheet(slug: slug)),
  );
}

class TermsAcceptSheet extends ConsumerStatefulWidget {
  const TermsAcceptSheet({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<TermsAcceptSheet> createState() => _TermsAcceptSheetState();
}

class _TermsAcceptSheetState extends ConsumerState<TermsAcceptSheet> {
  late final WebViewController _controller;
  String _title = '';
  bool _loading = true;
  bool _atBottom = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('MulindaScroll',
          onMessageReceived: (_) {
        if (mounted && !_atBottom) setState(() => _atBottom = true);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _controller.runJavaScript(_scrollWatcher),
      ));
    _load();
  }

  // Enables the button when the reader reaches the end — or immediately if the
  // document is shorter than the viewport (nothing to scroll).
  static const _scrollWatcher = '''
(function(){
  function check(){
    var atBottom = (window.innerHeight + window.scrollY) >= (document.body.scrollHeight - 32);
    if (atBottom && window.MulindaScroll) { MulindaScroll.postMessage('bottom'); }
  }
  window.addEventListener('scroll', check, {passive:true});
  window.addEventListener('resize', check);
  setTimeout(check, 400);
})();
''';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).get('/v1/pages/${widget.slug}');
      final data = (res.data['data'] as Map).cast<String, dynamic>();
      _title = data['title']?.toString() ?? 'Terms';
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
  a { color: ${hex(scheme.primary)}; } strong { font-weight: 600; }
  ul { padding-left: 1.2em; } em { color: ${hex(scheme.onSurfaceVariant)}; }
</style></head><body>$html<div style="height:40px"></div></body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? 'auth.terms'.tr() : _title),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
      ),
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
                Positioned.fill(child: WebViewWidget(controller: _controller)),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_atBottom && !_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Scroll to the end to continue',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _atBottom ? () => Navigator.pop(context, true) : null,
                  child: const Text('I have read and agree'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
