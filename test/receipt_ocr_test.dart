import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mulinda_mobile/features/capture/data/receipt_ocr.dart';

TextLine _line(String text, Rect box, {double? confidence}) => TextLine(
      text: text,
      elements: const [],
      boundingBox: box,
      recognizedLanguages: const [],
      cornerPoints: const <Point<int>>[],
      confidence: confidence,
      angle: 0,
    );

TextBlock _block(List<TextLine> lines) => TextBlock(
      text: lines.map((l) => l.text).join('\n'),
      lines: lines,
      boundingBox: lines.first.boundingBox,
      recognizedLanguages: const [],
      cornerPoints: const <Point<int>>[],
    );

void main() {
  test('ML Kit blocks flatten into reading-order lines with their block index', () {
    // ML Kit returns the amounts column as its own block, before the labels.
    final recognized = RecognizedText(text: '', blocks: [
      _block([
        _line('33,968.00', const Rect.fromLTRB(420, 1080, 580, 1110), confidence: 0.9),
        _line('35,000.00', const Rect.fromLTRB(500, 1090, 580, 1115)),
      ]),
      _block([
        _line('CHIPIKU PLUS', const Rect.fromLTRB(290, 410, 400, 430)),
        _line('   ', const Rect.fromLTRB(0, 500, 10, 510)),
        _line('TOTAL', const Rect.fromLTRB(158, 1078, 240, 1100)),
      ]),
    ]);

    final doc = OcrDocument.fromRecognizedText(recognized, source: 'chipiku.jpg');

    expect(doc.lines.map((l) => l.text), ['CHIPIKU PLUS', 'TOTAL', '33,968.00', '35,000.00']);
    expect(doc.lines.map((l) => l.block), [1, 1, 0, 0]);
    expect(doc.lines[2].confidence, 0.9);
    expect(doc.source, 'chipiku.jpg');
    expect(doc.engine, OcrDocument.engineMlKitLatin);
    expect(doc.text, 'CHIPIKU PLUS\nTOTAL\n33,968.00\n35,000.00');
  });

  test('a document survives a JSON round trip (fixture format)', () {
    const doc = OcrDocument(source: 'nbm.jpg', lines: [
      OcrLine(text: 'Payment/Send Amount', left: 55, top: 1170, right: 370, bottom: 1215, block: 3),
      OcrLine(text: 'MWK 10,000.00', left: 528, top: 1195, right: 855, bottom: 1250, block: 4, confidence: 0.97),
    ]);

    final restored = OcrDocument.fromJson(
      (jsonDecode(jsonEncode(doc.toJson())) as Map).cast<String, dynamic>(),
    );

    expect(restored.source, 'nbm.jpg');
    expect(restored.lines, hasLength(2));
    expect(restored.lines[1].text, 'MWK 10,000.00');
    expect(restored.lines[1].left, 528);
    expect(restored.lines[1].bottom, 1250);
    expect(restored.lines[1].block, 4);
    expect(restored.lines[1].confidence, 0.97);
    expect(restored.lines[0].confidence, isNull);
    expect(restored.lines[1].centerY, 1222.5);
  });
}
