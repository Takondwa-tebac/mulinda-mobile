import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_capture.dart';

/// Scripted phone: what the scanner, picker and cropper hand back. Shrinking
/// appends ".small"; discarded paths are recorded.
class _FakeDevice implements ReceiptCaptureDevice {
  _FakeDevice({this.scanned, this.scanError, this.picked, this.cropped, this.shrinkFails = false});

  final String? scanned;
  final Exception? scanError;
  final String? picked;
  final String? cropped;
  final bool shrinkFails;
  final calls = <String>[];
  final discarded = <String>[];

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

  @override
  Future<String?> shrink(String path) async {
    calls.add('shrink:$path');
    if (shrinkFails) throw StateError('decoder error');
    return '$path.small';
  }

  @override
  Future<void> discard(Iterable<String> paths) async => discarded.addAll(paths);
}

void main() {
  test('the camera button uses the document scanner, then shrinks its image', () async {
    final device = _FakeDevice(scanned: 'scan.jpg');

    expect(await ReceiptCapture(device).fromCamera(), 'scan.jpg.small');
    expect(device.calls, ['scan', 'shrink:scan.jpg']);
  });

  test('backing out of the scanner takes no photo and opens nothing else', () async {
    final device = _FakeDevice();

    expect(await ReceiptCapture(device).fromCamera(), isNull);
    expect(device.calls, ['scan']);
  });

  test('without the scanner, the plain camera is used, cropped and shrunk', () async {
    final device = _FakeDevice(scanError: const ScannerUnavailable('no Play services'), picked: 'photo.jpg', cropped: 'cropped.jpg');

    expect(await ReceiptCapture(device, requestCamera: () async => true).fromCamera(), 'cropped.jpg.small');
    expect(device.calls, ['scan', 'pick:camera', 'crop:photo.jpg', 'shrink:cropped.jpg']);
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

  test('a gallery image goes to the crop screen, then is shrunk', () async {
    final device = _FakeDevice(picked: 'gallery.jpg', cropped: 'cropped.jpg');

    expect(await ReceiptCapture(device).fromGallery(), 'cropped.jpg.small');
    expect(device.calls, ['pick:gallery', 'crop:gallery.jpg', 'shrink:cropped.jpg']);
  });

  test('a skipped crop is still shrunk: OCR never decodes a full-size photo', () async {
    final device = _FakeDevice(picked: 'screenshot.png');

    expect(await ReceiptCapture(device).fromGallery(), 'screenshot.png.small');
  });

  test('if shrinking fails the image is used as it is', () async {
    final device = _FakeDevice(picked: 'gallery.jpg', shrinkFails: true);

    expect(await ReceiptCapture(device).fromGallery(), 'gallery.jpg');
  });

  test('backing out of the gallery opens no crop screen', () async {
    final device = _FakeDevice();

    expect(await ReceiptCapture(device).fromGallery(), isNull);
    expect(device.calls, ['pick:gallery']);
  });

  test('every temporary file made is deleted, except the one being kept', () async {
    final device = _FakeDevice(picked: 'gallery.jpg', cropped: 'cropped.jpg');
    final capture = ReceiptCapture(device);
    final kept = await capture.fromGallery();

    await capture.discardAll(keep: kept);
    expect(device.discarded, unorderedEquals(['gallery.jpg', 'cropped.jpg']));

    await capture.discardAll();
    expect(device.discarded, contains('cropped.jpg.small'));
  });

  test('a retake leaves no files behind from the first photo', () async {
    final device = _FakeDevice(picked: 'gallery.jpg');
    final capture = ReceiptCapture(device);
    await capture.fromGallery();
    final second = await capture.recrop('gallery.jpg.small');

    await capture.discardAll(keep: second);
    expect(device.discarded, containsAll(['gallery.jpg', 'gallery.jpg.small']));
  });
}
