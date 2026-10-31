import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// One line of text read from a receipt image, with where it sits on the
/// image (pixels, origin top-left). Positions let the parser pair a label such
/// as "TOTAL" with the amount printed on the same row.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.block,
    this.confidence,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Index of the ML Kit text block this line came from; lines in one block
  /// were laid out together on the receipt.
  final int block;

  /// ML Kit's confidence for the line (Android only; null on iOS).
  final double? confidence;

  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;

  Map<String, dynamic> toJson() => {
        'text': text,
        'box': [left, top, right, bottom],
        'block': block,
        if (confidence != null) 'confidence': confidence,
      };

  factory OcrLine.fromJson(Map<String, dynamic> json) {
    final box = (json['box'] as List).map((v) => (v as num).toDouble()).toList();
    return OcrLine(
      text: json['text'] as String,
      left: box[0],
      top: box[1],
      right: box[2],
      bottom: box[3],
      block: json['block'] as int,
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
}

/// The text read from one receipt image, decoupled from ML Kit's types so the
/// parser can be tested on saved JSON fixtures without a device.
class OcrDocument {
  const OcrDocument({required this.lines, this.engine = engineMlKitLatin, this.source});

  static const engineMlKitLatin = 'mlkit-latin';

  final List<OcrLine> lines;

  /// Which OCR produced this document, so fixtures from a future engine can be
  /// told apart.
  final String engine;

  /// The image file name, used to match a fixture to its answers.csv row.
  final String? source;

  String get text => lines.map((l) => l.text).join('\n');

  bool get isEmpty => lines.isEmpty;

  Map<String, dynamic> toJson() => {
        'engine': engine,
        if (source != null) 'source': source,
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  factory OcrDocument.fromJson(Map<String, dynamic> json) => OcrDocument(
        engine: json['engine'] as String? ?? engineMlKitLatin,
        source: json['source'] as String?,
        lines: (json['lines'] as List)
            .map((l) => OcrLine.fromJson((l as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// Flattens ML Kit's blocks into lines, sorted top-to-bottom then
  /// left-to-right (ML Kit's own block order is not reading order).
  factory OcrDocument.fromRecognizedText(RecognizedText recognized, {String? source}) {
    final lines = <OcrLine>[
      for (final (i, block) in recognized.blocks.indexed)
        for (final line in block.lines)
          if (line.text.trim().isNotEmpty)
            OcrLine(
              text: line.text.trim(),
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
              block: i,
              confidence: line.confidence,
            ),
    ]..sort((a, b) {
        final byRow = a.top.compareTo(b.top);
        return byRow != 0 ? byRow : a.left.compareTo(b.left);
      });
    return OcrDocument(lines: lines, source: source);
  }
}

/// Reads the text on a receipt image, entirely on the device.
abstract class ReceiptOcr {
  Future<OcrDocument> read(String imagePath, {String? source});

  /// Releases the native recognizer.
  Future<void> close();
}

/// Google ML Kit's on-device Latin text recognizer: free, offline, no upload.
class MlKitReceiptOcr implements ReceiptOcr {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<OcrDocument> read(String imagePath, {String? source}) async {
    final recognized = await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    return OcrDocument.fromRecognizedText(recognized, source: source);
  }

  @override
  Future<void> close() => _recognizer.close();
}

final receiptOcrProvider = Provider<ReceiptOcr>((ref) {
  final ocr = MlKitReceiptOcr();
  ref.onDispose(ocr.close);
  return ocr;
});
