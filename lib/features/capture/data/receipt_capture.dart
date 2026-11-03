import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

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
}

/// Getting a receipt image the way that reads best, falling back when a step
/// is not available:
/// - camera: the document scanner; if it can't run, the plain camera and
///   then the crop screen;
/// - gallery: the picker, then the crop screen (cancelling the crop keeps the
///   whole image, which is right for an app screenshot).
class ReceiptCapture {
  ReceiptCapture(this.device, {this.requestCamera});

  final ReceiptCaptureDevice device;

  /// Asks for the camera permission before the plain camera opens; false
  /// means refused. The scanner asks on its own.
  final Future<bool> Function()? requestCamera;

  Future<String?> fromCamera() async {
    try {
      return await device.scan();
    } on ScannerUnavailable catch (e) {
      debugPrint('receipt scanner unavailable, using the camera: ${e.reason}');
    }
    if (requestCamera != null && !await requestCamera!()) throw const CameraDenied();
    final photo = await device.pick(ImageSource.camera);
    if (photo == null) return null;
    return await device.crop(photo) ?? photo;
  }

  Future<String?> fromGallery() async {
    final picked = await device.pick(ImageSource.gallery);
    if (picked == null) return null;
    return await device.crop(picked) ?? picked;
  }

  /// Crop an image already chosen; null keeps it as it is.
  Future<String?> recrop(String path) => device.crop(path);
}

final receiptCaptureDeviceProvider = Provider<ReceiptCaptureDevice>(
  (ref) => NativeReceiptCaptureDevice(cropTitle: () => 'receipt.cropTitle'.tr(), cropColor: AppColors.teal),
);
