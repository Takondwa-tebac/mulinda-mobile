import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_capture.dart';

/// Scripted phone: what the scanner, picker and cropper hand back.
class _FakeDevice implements ReceiptCaptureDevice {
  _FakeDevice({this.scanned, this.scanError, this.picked, this.cropped});

  final String? scanned;
  final Exception? scanError;
  final String? picked;
  final String? cropped;
  final calls = <String>[];

  @override
  Future<String?> scan() async {
    calls.add('scan');
    if (scanError != null) throw scanError!;
    return scanned;
  }

  @override
  Future<String?> pick(ImageSource source) async {
    calls.add('pick:${source.name}');
    return picked;
  }

  @override
  Future<String?> crop(String path) async {
    calls.add('crop:$path');
    return cropped;
  }
}

void main() {
  test('the camera button uses the document scanner, which crops by itself', () async {
    final device = _FakeDevice(scanned: 'scan.jpg');

    expect(await ReceiptCapture(device).fromCamera(), 'scan.jpg');
    expect(device.calls, ['scan']);
  });

  test('backing out of the scanner takes no photo and opens nothing else', () async {
    final device = _FakeDevice();

    expect(await ReceiptCapture(device).fromCamera(), isNull);
    expect(device.calls, ['scan']);
  });

  test('without the scanner, the plain camera is used and then cropped', () async {
    final device = _FakeDevice(scanError: const ScannerUnavailable('no Play services'), picked: 'photo.jpg', cropped: 'cropped.jpg');

    expect(await ReceiptCapture(device, requestCamera: () async => true).fromCamera(), 'cropped.jpg');
    expect(device.calls, ['scan', 'pick:camera', 'crop:photo.jpg']);
  });

  test('the fallback camera still asks for the camera permission', () async {
    final device = _FakeDevice(scanError: const ScannerUnavailable('no Play services'), picked: 'photo.jpg');

    expect(() => ReceiptCapture(device, requestCamera: () async => false).fromCamera(), throwsA(isA<CameraDenied>()));
  });

  test('a refused camera in the scanner is reported, not retried with the camera', () async {
    final device = _FakeDevice(scanError: const CameraDenied());

    await expectLater(ReceiptCapture(device).fromCamera(), throwsA(isA<CameraDenied>()));
    expect(device.calls, ['scan']);
  });

  test('a gallery image goes to the crop screen', () async {
    final device = _FakeDevice(picked: 'gallery.jpg', cropped: 'cropped.jpg');

    expect(await ReceiptCapture(device).fromGallery(), 'cropped.jpg');
    expect(device.calls, ['pick:gallery', 'crop:gallery.jpg']);
  });

  test('cancelling the crop keeps the whole image (an app screenshot needs none)', () async {
    final device = _FakeDevice(picked: 'screenshot.png');

    expect(await ReceiptCapture(device).fromGallery(), 'screenshot.png');
  });

  test('backing out of the gallery opens no crop screen', () async {
    final device = _FakeDevice();

    expect(await ReceiptCapture(device).fromGallery(), isNull);
    expect(device.calls, ['pick:gallery']);
  });
}
