import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/features/feature_flags.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/permissions/permission_service.dart';
import '../../auth/providers/auth_controller.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/widgets/premium_lock.dart';
import '../data/inbox_repository.dart';
import '../data/receipt_capture.dart';
import '../data/receipt_scanner.dart';

class ScanReceiptScreen extends ConsumerStatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  ConsumerState<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends ConsumerState<ScanReceiptScreen> {
  /// The receipt image to upload: cropped to the receipt where possible, as
  /// the on-device reader (and the AI fallback) read a tight crop far better.
  String? _image;

  /// One per image: a retry after a timeout must not store the receipt twice.
  String _clientId = ReceiptScanner.newClientId();
  bool _loading = false;

  ReceiptCapture get _capture => ReceiptCapture(
        ref.read(receiptCaptureDeviceProvider),
        requestCamera: ref.read(permissionServiceProvider).requestCamera,
      );

  Future<void> _take(Future<String?> Function() capture) async {
    try {
      final path = await capture();
      if (path != null && mounted) {
        setState(() {
          _image = path;
          _clientId = ReceiptScanner.newClientId();
        });
      }
    } on CameraDenied {
      _snack('receipt.cameraDenied'.tr());
    } catch (e) {
      debugPrint('receipt capture failed: $e');
      _snack('receipt.captureFailed'.tr());
    }
  }

  Future<void> _submit() async {
    final image = _image;
    if (image == null) return;
    setState(() => _loading = true);
    try {
      // Wait for the flags rather than read "off" while they are still
      // loading: that sent the photo alone to the AI, and the same receipt
      // scanned again a moment later was read on the phone, a second scan.
      Future<Map<String, bool>> readFlags() => ref
          .read(featureFlagsProvider.future)
          .timeout(const Duration(seconds: 5), onTimeout: () => const <String, bool>{});
      var flags = await readFlags();
      if (flags.isEmpty) {
        // A failed fetch is remembered for the session; try once more.
        ref.invalidate(featureFlagsProvider);
        flags = await readFlags();
      }
      final onDevice = flags[FeatureKeys.receiptOnDevice] ?? false;
      final result = await ref.read(receiptScannerProvider).scan(image, onDevice: onDevice, clientId: _clientId);
      if (!mounted) return;
      ref.invalidate(pendingReceiptsProvider);
      switch (result.outcome) {
        case ReceiptScanOutcome.ready:
          _snack(result.duplicateTransactionId != null
              ? 'receipt.readyDuplicate'.tr()
              : 'receipt.ready'.tr());
          context.pushReplacement(Routes.inbox);
        case ReceiptScanOutcome.pending:
          _snack('receipt.queued'.tr());
          Navigator.of(context).pop();
        case ReceiptScanOutcome.notReceipt:
          setState(() => _loading = false);
          _snack('receipt.notReceipt'.tr());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loading = false);
      if (e.code == 'ai_rate_limited') {
        await _offerManualEntry();
      } else {
        _snack(e.displayMessage);
      }
    }
  }

  /// Scanning is paused (the AI service is busy): offer to add the expense by hand.
  Future<void> _offerManualEntry() async {
    if (!mounted) return;
    final addNow = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('receipt.busyTitle'.tr()),
        content: Text('receipt.busyBody'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('form.cancel'.tr())),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('receipt.addByHand'.tr())),
        ],
      ),
    );
    if (addNow == true && mounted) {
      Navigator.of(context).pop();
      context.push(Routes.addTransaction);
    }
  }

  /// Debug builds get a shortcut to the OCR fixture tool.
  AppBar _appBar() => AppBar(
        title: Text('receipt.title'.tr()),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Receipt OCR (debug)',
              onPressed: () => context.push(Routes.receiptOcrDebug),
              icon: const Icon(Icons.bug_report_outlined),
            ),
        ],
      );

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Reading on the phone is free for everyone; without it (kill switch, older
    // server) scanning falls back to the server's AI, which is premium.
    final onDevice = ref.watch(featureEnabledProvider(FeatureKeys.receiptOnDevice));
    final entitled =
        ref.watch(currentUserProvider)?.can(Entitlements.receiptScan) ?? false;
    if (!onDevice && !entitled && ref.watch(featureFlagsProvider).isLoading) {
      return Scaffold(appBar: _appBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (!onDevice && !entitled) {
      return Scaffold(
        appBar: _appBar(),
        body: PremiumLockView(
          title: 'capture.lockedTitle'.tr(),
          message: 'capture.lockedReceipt'.tr(),
          icon: Icons.document_scanner_outlined,
        ),
      );
    }

    return Scaffold(
      appBar: _appBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('receipt.subtitle'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('receipt.tip'.tr(), style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _image == null
                      ? Center(child: Icon(Icons.receipt_long, size: 56, color: scheme.outline))
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(_image!), fit: BoxFit.contain),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: FilledButton.tonalIcon(
                                onPressed: _loading ? null : () => _take(() async => await _capture.recrop(_image!) ?? _image),
                                icon: const Icon(Icons.crop),
                                label: Text('receipt.crop'.tr()),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _take(_capture.fromCamera),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: Text(_image == null ? 'receipt.takePhoto'.tr() : 'receipt.retake'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _take(_capture.fromGallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text('receipt.chooseImage'.tr()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_image == null || _loading) ? null : _submit,
                child: _loading
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onPrimary),
                      )
                    : Text('receipt.submit'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
