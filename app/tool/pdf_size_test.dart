// Measures the size of a typical 10-page PDF made by the real pipeline
// (native OpenCV: detect -> flatten -> Magic Color -> PDF) from the shared
// test photos, for the stored page settings in use and some alternatives.
//   tool/host_test.sh tool/pdf_size_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:docscanner/imaging/page_edits.dart';
import 'package:docscanner/imaging/scan_engine.dart';
import 'package:docscanner/services/export/pdf_builder.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;

const photos = [
  'tilted_paper',
  'strong_perspective',
  'shadow_across',
  'cluttered_background',
  'low_contrast',
  'fills_frame',
  'narrow_receipt',
];

void main() {
  test('10-page PDF size', () async {
    final engine = ScanEngine();
    await engine.ready;
    final dir = '../shared/test_fixtures';
    // Same camera-size photos as a phone: the fixtures upscaled to 12 MP (3024x4032).
    final sources = <Uint8List>[];
    final rnd = Random(1);
    for (var i = 0; i < 10; i++) {
      final f = File('$dir/${photos[i % photos.length]}.jpg').readAsBytesSync();
      // Upscale to 12 MP, then add sensor-like noise (sigma ~6) as a phone camera has;
      // clean synthetic photos would make every PDF look unrealistically small.
      final small = img.decodeJpg(f)!;
      final big = small.width > small.height
          ? img.copyResize(small, width: 4032, height: 3024, interpolation: img.Interpolation.cubic)
          : img.copyResize(small, width: 3024, height: 4032, interpolation: img.Interpolation.cubic);
      for (final px in big) {
        final n = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * 12;
        px
          ..r = (px.r + n).clamp(0, 255)
          ..g = (px.g + n).clamp(0, 255)
          ..b = (px.b + n).clamp(0, 255);
      }
      sources.add(Uint8List.fromList(img.encodeJpg(big, quality: 92)));
    }
    // ignore: avoid_print
    print('source photo: ${(sources.first.length / 1048576).toStringAsFixed(1)} MB');
    // (flat max side, render quality) — the first is what the app uses.
    for (final (maxSide, quality) in [(3200, 90), (3200, 85), (2480, 90), (2480, 85), (2480, 80)]) {
      final pages = <PdfPageInput>[];
      var renders = 0;
      for (final src in sources) {
        final det = await engine.detectEncoded(src);
        final flat = await engine.warpEncoded(src, det.detection.corners, maxSide: maxSide);
        final render = await engine.processEncoded(flat, const PageEdits(filter: PageFilter.magicColor), quality: quality);
        renders += render.length;
        final (w, h) = await _size(render);
        pages.add(PdfPageInput(jpeg: render, width: w, height: h));
      }
      final pdf = await buildPdf(pages);
      // ignore: avoid_print
      print(
        'flat ${maxSide}px, JPEG q$quality: PDF ${(pdf.length / 1048576).toStringAsFixed(2)} MB '
        '(${(renders / 10 / 1024).round()} KB per page)',
      );
    }
    engine.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Width/height from the JPEG header.
Future<(int, int)> _size(Uint8List jpeg) async {
  var i = 2;
  while (i < jpeg.length) {
    final marker = jpeg[i + 1];
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (marker >= 0xC0 && marker <= 0xC2) {
      return ((jpeg[i + 7] << 8) | jpeg[i + 8], (jpeg[i + 5] << 8) | jpeg[i + 6]);
    }
    i += 2 + len;
  }
  throw StateError('no JPEG size');
}
