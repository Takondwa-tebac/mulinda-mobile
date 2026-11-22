import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/referral_repository.dart';
import '../invite_message.dart';

/// The invite QR code (Mulinda logo in the middle, invite code underneath),
/// what to do with it, and "Save image" / "Share image". The saved and shared
/// picture is exactly the white card shown here.
class ReferralQrPanel extends StatefulWidget {
  const ReferralQrPanel({super.key, required this.info});

  final ReferralInfo info;

  @override
  State<ReferralQrPanel> createState() => _ReferralQrPanelState();
}

enum _Busy { none, saving, sharing }

class _ReferralQrPanelState extends State<ReferralQrPanel> {
  static const _logo = AssetImage('assets/logo.png');

  /// The QR's size on screen, shrunk to fit narrow sheets.
  static const double _qrSize = 200;

  final _cardKey = GlobalKey(debugLabel: 'referral-qr-card');
  _Busy _busy = _Busy.none;

  String get _fileName => 'mulinda-invite-${widget.info.code}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // So the logo is already in the picture when it is saved or shared.
    precacheImage(_logo, context);
  }

  /// The white card as a PNG.
  Future<Uint8List> _renderPng() async {
    final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ratio = math.max(3.0, MediaQuery.devicePixelRatioOf(context));
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(key.tr())));
  }

  Future<void> _save() async {
    setState(() => _busy = _Busy.saving);
    try {
      final bytes = await _renderPng();
      // Android 11 and later need no permission to add a picture; older
      // versions ask once for storage.
      final allowed =
          await Gal.hasPermission(toAlbum: true) || await Gal.requestPermission(toAlbum: true);
      if (!allowed) {
        _snack('referral.qrSaveDenied');
        return;
      }
      await Gal.putImageBytes(bytes, album: 'Mulinda', name: _fileName);
      Analytics.track('referral_qr_saved', const {});
      _snack('referral.qrSaved');
    } on GalException catch (e) {
      _snack(e.type == GalExceptionType.permissionDenied ? 'referral.qrSaveDenied' : 'referral.qrSaveFailed');
    } catch (_) {
      _snack('referral.qrSaveFailed');
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = _Busy.sharing);
    try {
      final bytes = await _renderPng();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_fileName.png');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final text = inviteMessage(widget.info, context.locale.languageCode);
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: text,
      );
      if (result.status == ShareResultStatus.success) {
        Analytics.track('referral_qr_shared', const {});
        _snack('referral.qrShared');
      }
    } catch (_) {
      _snack('referral.qrShareFailed');
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5);

    return LayoutBuilder(
      builder: (context, constraints) {
        final qrSize = math.min(_qrSize, constraints.maxWidth - 2 * AppSpacing.lg);
        // Side by side when both labels fit, stacked on narrow screens or
        // with large text.
        final sideBySide = constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(300);
        final actions = [
          _ActionButton(
            key: const ValueKey('referral-qr-save'),
            icon: Icons.download_rounded,
            label: 'referral.qrSave'.tr(),
            busy: _busy == _Busy.saving,
            onPressed: _busy == _Busy.none ? _save : null,
          ),
          _ActionButton(
            key: const ValueKey('referral-qr-share'),
            icon: Icons.share_rounded,
            label: 'referral.qrShare'.tr(),
            busy: _busy == _Busy.sharing,
            onPressed: _busy == _Busy.none ? _share : null,
          ),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: RepaintBoundary(
                key: _cardKey,
                child: _QrCard(link: widget.info.link, code: widget.info.code, size: qrSize, logo: _logo),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('referral.qrBody'.tr(), textAlign: TextAlign.center, style: body),
            const SizedBox(height: AppSpacing.lg),
            if (sideBySide)
              Row(
                children: [
                  Expanded(child: actions[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: actions[1]),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [actions[0], const SizedBox(height: AppSpacing.sm), actions[1]],
              ),
          ],
        );
      },
    );
  }
}

/// Dark on white in both themes so any camera can read it, and so the saved
/// picture looks the same whatever theme it was saved from.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.link, required this.code, required this.size, required this.logo});

  final String link;
  final String code;
  final double size;
  final ImageProvider logo;

  @override
  Widget build(BuildContext context) {
    final logoSize = size * 0.22;
    return ColoredBox(
      color: AppColors.white,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: link,
                    size: size,
                    padding: EdgeInsets.zero,
                    // High error correction so the logo on top never stops it
                    // from scanning.
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    backgroundColor: AppColors.white,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.ink),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.ink,
                    ),
                    semanticsLabel: 'referral.qrLabel'.tr(),
                  ),
                  ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Image(image: logo, width: logoSize, height: logoSize),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'referral.codeLabel'.tr(),
              style: const TextStyle(fontSize: 13, color: AppColors.inkVariant),
            ),
            Text(
              code,
              key: const ValueKey('referral-qr-code'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({super.key, required this.icon, required this.label, required this.busy, this.onPressed});

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.minTouch)),
      onPressed: onPressed,
      icon: busy
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
