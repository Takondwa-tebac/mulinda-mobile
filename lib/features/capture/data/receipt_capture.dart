import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';

/// The document scanner could not run on this phone (no Google Play
/// services, an old iOS, a plugin error), as opposed to the user cancelling.
class ScannerUnavailable implements Exception {
  const ScannerUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'ScannerUnavailable: $reason';
}

/// The camera permission was refused, so neither the scanner nor the camera
/// can take a photo.
class CameraDenied implements Exception {
  const CameraDenied();
}

/// The phone's ways of getting a receipt image. Each returns a file path, or
/// null when the user backs out.
abstract class ReceiptCaptureDevice {
  /// The document scanner: a live camera that outlines the receipt, then
  /// crops and straightens it. Throws [ScannerUnavailable] or [CameraDenied].
  Future<String?> scan();

  /// The plain camera or gallery picker.
  Future<String?> pick(ImageSource source);

  /// A crop and rotate screen over [path]. Null when the user cancels.
  Future<String?> crop(String path);

  /// [path] as a JPEG no longer than [ReceiptCapture.maxImageSide] on its long
  /// side, upright, with its EXIF (GPS location included) removed. Null keeps
  /// [path] as it is.
  Future<String?> shrink(String path);

  /// Deletes [path] if it is a temporary file (picker copy, crop, shrunk
  /// copy), never a user's own photo; and the scanner's cache.
  Future<void> discard(Iterable<String> paths);
}

/// Native implementation: Google ML Kit's document scanner on Android
/// (delivered by Play services), VisionKit's document camera on iOS, and
/// uCrop / TOCropViewController for cropping.
class NativeReceiptCaptureDevice implements ReceiptCaptureDevice {
  NativeReceiptCaptureDevice({required this.cropTitle, required this.cropColor});

  /// Shown on the crop screen's toolbar.
  final String Function() cropTitle;
  final Color cropColor;

  final _picker = ImagePicker();

  @override
  Future<String?> scan() async {
    try {
      final pages = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        scannerSource: ScannerSource.camera,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.85,
          showFilterBar: false,
        ),
      );
      return pages?.first;
    } on CunningDocumentScannerException catch (e) {
      if (e.code == 'permission_denied') throw const CameraDenied();
      throw ScannerUnavailable(e.toString());
    } on MissingPluginException catch (e) {
      throw ScannerUnavailable(e.toString());
    }
  }

  @override
  Future<String?> pick(ImageSource source) async {
    // Same compression the scan screen has always used.
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    return picked?.path;
  }

  @override
  Future<String?> crop(String path) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      compressQuality: 85,
      // The crop is taken from the full photo, then capped: 2400 px is ample
      // for ML Kit to read receipt print, and a 12 MP photo decoded for OCR
      // would cost an entry-level phone seconds and ~50 MB of memory.
      maxWidth: ReceiptCapture.maxImageSide,
      maxHeight: ReceiptCapture.maxImageSide,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: cropTitle(),
          toolbarColor: cropColor,
          toolbarWidgetColor: AppColors.onTeal,
          activeControlsWidgetColor: cropColor,
          // Till slips are long and thin: no fixed ratio.
          lockAspectRatio: false,
          initAspectRatio: CropAspectRatioPreset.original,
        ),
        IOSUiSettings(title: cropTitle(), aspectRatioLockEnabled: false, resetAspectRatioEnabled: true),
      ],
    );
    return cropped?.path;
  }

  @override
  Future<String?> shrink(String path) async {
    // The header alone gives the size; nothing is decoded in Dart.
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longSide = math.max(descriptor.width, descriptor.height);
    final shortSide = math.min(descriptor.width, descriptor.height);
    descriptor.dispose();
    buffer.dispose();

    // The plugin's "min" sizes bound the shorter side; giving both the same
    // value caps the long side whichever way the photo is rotated.
    final scale = math.min(1.0, ReceiptCapture.maxImageSide / longSide);
    final bound = (shortSide * scale).round();
    final target = '${(await getTemporaryDirectory()).path}/receipt_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final out = await FlutterImageCompress.compressAndGetFile(
      path,
      target,
      minWidth: bound,
      minHeight: bound,
      quality: 85,
      autoCorrectionAngle: true,
      keepExif: false,
    );
    return out?.path;
  }

  @override
  Future<void> discard(Iterable<String> paths) async {
    final temp = {(await getTemporaryDirectory()).path, Directory.systemTemp.path};
    for (final path in paths) {
      if (!temp.any(path.startsWith)) continue;
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    try {
      await CunningDocumentScanner.cleanCache();
    } catch (_) {}
  }
}

/// Getting a receipt image the way that reads best, falling back when a step
/// is not available:
/// - camera: the document scanner; if it can't run, the plain camera and
///   then the crop screen;
/// - gallery: the picker, then the crop screen (cancelling the crop keeps the
///   whole image, which is right for an app screenshot).
///
/// Every image handed back is shrunk to [maxImageSide]: OCR then decodes at
/// most ~5 MP however the image arrived (a skipped crop, a 50 MP camera).
/// Every file made along the way is remembered and deleted by [discardAll],
/// so scans don't pile up in the phone's storage.
class ReceiptCapture {
  ReceiptCapture(this.device, {this.requestCamera});

  /// Longest side of a receipt image: ample for ML Kit to read receipt print,
  /// where a 12 MP photo would cost an entry-level phone ~50 MB to decode.
  static const maxImageSide = 2400;

  final ReceiptCaptureDevice device;

  /// Asks for the camera permission before the plain camera opens; false
  /// means refused. The scanner asks on its own.
  final Future<bool> Function()? requestCamera;

  final _made = <String>{};

  Future<String?> fromCamera() async {
    try {
      return await _finish(await device.scan());
    } on ScannerUnavailable catch (e) {
      debugPrint('receipt scanner unavailable, using the camera: ${e.reason}');
    }
    if (requestCamera != null && !await requestCamera!()) throw const CameraDenied();
    final photo = _made.track(await device.pick(ImageSource.camera));
    if (photo == null) return null;
    return _finish(_made.track(await device.crop(photo)) ?? photo);
  }

  Future<String?> fromGallery() async {
    final picked = _made.track(await device.pick(ImageSource.gallery));
    if (picked == null) return null;
    return _finish(_made.track(await device.crop(picked)) ?? picked);
  }

  /// Crop an image already chosen; null keeps it as it is.
  Future<String?> recrop(String path) async {
    final cropped = _made.track(await device.crop(path));
    return cropped == null ? null : _finish(cropped);
  }

  /// Deletes every temporary file this capture made, except [keep].
  Future<void> discardAll({String? keep}) async {
    final paths = _made.where((p) => p != keep).toList();
    _made.removeAll(paths);
    await device.discard(paths);
  }

  Future<String?> _finish(String? path) async {
    if (path == null) return null;
    _made.add(path);
    try {
      return _made.track(await device.shrink(path)) ?? path;
    } catch (e) {
      debugPrint('receipt shrink failed, using the image as is: $e');
      return path;
    }
  }
}

extension on Set<String> {
  String? track(String? path) {
    if (path != null) add(path);
    return path;
  }
}

final receiptCaptureDeviceProvider = Provider<ReceiptCaptureDevice>(
  (ref) => NativeReceiptCaptureDevice(cropTitle: () => 'receipt.cropTitle'.tr(), cropColor: AppColors.teal),
);
