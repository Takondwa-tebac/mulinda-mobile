import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/permissions/permission_service.dart';
import '../../activity/data/activity_repository.dart';
import '../../auth/providers/auth_controller.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/widgets/premium_lock.dart';

class ScanReceiptScreen extends ConsumerStatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  ConsumerState<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends ConsumerState<ScanReceiptScreen> {
  final _picker = ImagePicker();
  XFile? _image;
  bool _loading = false;

  Future<void> _pick(ImageSource source) async {
    if (source == ImageSource.camera) {
      final granted = await ref.read(permissionServiceProvider).requestCamera();
      if (!granted) {
        _snack('receipt.cameraDenied'.tr());
        return;
      }
    }
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) setState(() => _image = picked);
  }

  Future<void> _submit() async {
    final image = _image;
    if (image == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(activityRepositoryProvider).scanReceipt(image.path);
      if (mounted) {
        _snack('receipt.queued'.tr());
        Navigator.of(context).pop();
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // AI receipt extraction is premium — gate the screen behind a subscription.
    final entitled =
        ref.watch(currentUserProvider)?.can(Entitlements.receiptScan) ?? false;
    if (!entitled) {
      return Scaffold(
        appBar: AppBar(title: Text('receipt.title'.tr())),
        body: PremiumLockView(
          title: 'capture.lockedTitle'.tr(),
          message: 'capture.lockedReceipt'.tr(),
          icon: Icons.document_scanner_outlined,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('receipt.title'.tr())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('receipt.subtitle'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
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
                      : Image.file(File(_image!.path), fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text('receipt.takePhoto'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _pick(ImageSource.gallery),
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
