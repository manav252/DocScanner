// Exercises the isolate-backed ScanEngine used on Android/iOS.
import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/imaging/scan_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'fixtures.dart';

void main() {
  late ScanEngine detector;
  setUpAll(() async {
    detector = ScanEngine();
    await detector.ready;
  });
  tearDownAll(() => detector.dispose());

  test('detectEncoded runs on the background isolate', () async {
    final bytes = File('${fixturesDir.path}/tilted_paper.jpg').readAsBytesSync();
    final r = await detector.detectEncoded(bytes);
    expect((r.width, r.height), (imageWidth, imageHeight));
    expect(r.detection.found, isTrue);
    expect(
      maxCornerError(r.detection.corners, cornersOf((cases['tilted_paper'] as Map)['corners'])),
      lessThan(tolerance),
    );
  });

  test('detectFrame accepts luma, BGRA and RGBA frames', () async {
    final img = cv.imread('${fixturesDir.path}/strong_perspective.jpg');
    final expected = cornersOf((cases['strong_perspective'] as Map)['corners']);
    final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
    final bgra = cv.cvtColor(img, cv.COLOR_BGR2BGRA);
    final rgba = cv.cvtColor(img, cv.COLOR_BGR2RGBA);
    for (final (bytes, format) in [
      (gray.data, PixelFormat.luma),
      (bgra.data, PixelFormat.bgra),
      (rgba.data, PixelFormat.rgba),
    ]) {
      final d = await detector.detectFrame(FrameData(bytes: bytes, width: img.cols, height: img.rows, format: format));
      expect(d.found, isTrue, reason: '$format');
      expect(maxCornerError(d.corners, expected), lessThan(tolerance), reason: '$format');
    }
  });

  test('errors come back as exceptions, not hangs', () async {
    await expectLater(detector.detectEncoded(Uint8List.fromList([0, 1, 2])), throwsStateError);
  });

  test('concurrent requests resolve independently', () async {
    final names = ['tilted_paper', 'no_document', 'low_contrast'];
    final rs = await Future.wait([
      for (final n in names) detector.detectEncoded(File('${fixturesDir.path}/$n.jpg').readAsBytesSync()),
    ]);
    expect([for (final r in rs) r.detection.found], [true, false, true]);
  });
}
