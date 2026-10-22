// Renders shared/test_fixtures/ocr/hindi_page.png (correctly shaped Devanagari via
// Flutter's text engine + Noto Sans Devanagari). Run:
//   flutter test tool/render_ocr_fixture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const lines = [
  'भारत एक विशाल देश है।',
  'यह दस्तावेज़ स्कैनर का परीक्षण है।',
  'कुल राशि: 1250 रुपये',
  'दिनांक: 22 अक्टूबर 2026',
];

void main() {
  testWidgets('render Hindi OCR fixture', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('NotoDeva')
        ..addFont(Future.value(ByteData.sublistView(File('assets/fonts/NotoSansDevanagari-Regular.ttf').readAsBytesSync())));
      await font.load();
      const w = 1400.0, h = 520.0;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
      var y = 60.0;
      for (final line in lines) {
        final tp = TextPainter(
          text: TextSpan(text: line, style: const TextStyle(fontFamily: 'NotoDeva', fontSize: 52, color: Colors.black)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(70, y));
        y += 105;
      }
      final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('../shared/test_fixtures/ocr/hindi_page.png').writeAsBytesSync(png!.buffer.asUint8List());
      File('../shared/test_fixtures/ocr/hindi_page.txt').writeAsStringSync('${lines.join('\n')}\n');
    });
  });
}
