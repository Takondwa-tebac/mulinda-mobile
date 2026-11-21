import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../checkout_flow.dart';

/// Hosts a PayChangu hosted-checkout page. Pops with [CheckoutExit.returned]
/// when PayChangu sends the person back to our return URL, or
/// [CheckoutExit.closed] when they leave themselves (after confirming). The
/// caller then asks the server what really happened — the return URL's status
/// parameter is never trusted.
class CheckoutWebViewScreen extends StatefulWidget {
  const CheckoutWebViewScreen({super.key, required this.checkoutUrl});

  final String checkoutUrl;

  @override
  State<CheckoutWebViewScreen> createState() => _CheckoutWebViewScreenState();
}

/// Markers in a navigation URL that mean checkout has concluded.
const checkoutReturnMarkers = [
  'changu-hook',
  '/payment/return',
  'payment-complete',
];

/// Whether [url] is where the payment page sends people when it is done.
bool isCheckoutReturnUrl(String url) {
  final lower = url.toLowerCase();
  return checkoutReturnMarkers.any(lower.contains);
}

class _CheckoutWebViewScreenState extends State<CheckoutWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            if (isCheckoutReturnUrl(request.url)) {
              _finish(CheckoutExit.returned);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _finish(CheckoutExit exit) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(exit);
  }

  /// Leaving mid-payment: a mobile-money approval may still be on its way, so
  /// ask first rather than abandoning it by accident.
  Future<void> _confirmClose() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('paywall.checkout.leaveTitle'.tr()),
        content: Text('paywall.checkout.leaveBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('paywall.checkout.stay'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('paywall.checkout.leave'.tr()),
          ),
        ],
      ),
    );
    if (leave == true) _finish(CheckoutExit.closed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('paywall.checkout.title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmClose,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
