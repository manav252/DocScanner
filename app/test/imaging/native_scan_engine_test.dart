// Exercises the isolate-backed ScanEngine used on Android/iOS.
import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/imaging/geometry.dart';
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

  /// [img] (BGR) as an Android camera frame: Y plane with padded rows, U/V
  /// interleaved (pixel stride 2) as YUV_420_888 gives them.
  FrameData yuvFrame(cv.Mat img) {
    final w = img.cols, h = img.rows, stride = w + 32;
    final yuv = cv.cvtColor(img, cv.COLOR_BGR2YUV);
    final d = yuv.data;
    final y = Uint8List(stride * h);
    for (var r = 0; r < h; r++) {
      for (var c = 0; c < w; c++) {
        y[r * stride + c] = d[(r * w + c) * 3];
      }
    }
    final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2, uvStride = cw * 2;
    final uv = Uint8List(uvStride * ch);
    for (var r = 0; r < ch; r++) {
      for (var c = 0; c < cw; c++) {
        final i = ((2 * r) * w + 2 * c) * 3;
        uv[r * uvStride + 2 * c] = d[i + 1];
        uv[r * uvStride + 2 * c + 1] = d[i + 2];
      }
    }
    yuv.dispose();
    return FrameData(
      bytes: y,
      width: w,
      height: h,
      rowStride: stride,
      format: PixelFormat.yuv420,
      u: uv,
      v: Uint8List.sublistView(uv, 1),
      uvRowStride: uvStride,
      uvPixelStride: 2,
    );
  }

  test('Android YUV frames: same corners as the colour photo', () async {
    final img = cv.imread('${fixturesDir.path}/strong_perspective.jpg');
    final expected = cornersOf((cases['strong_perspective'] as Map)['corners']);
    final d = await detector.detectFrame(yuvFrame(img));
    expect(d.found, isTrue);
    expect(maxCornerError(d.corners, expected), lessThan(tolerance));
  });

  test('Android YUV frames use colour: a grey page on a yellow cloth of the same brightness', () async {
    // Grey page (luma 204) on yellow (luma ~204): invisible in brightness alone.
    final img = cv.Mat.fromScalar(800, 600, cv.MatType.CV_8UC3, cv.Scalar(0, 230, 231));
    cv.fillPoly(
      img,
      cv.VecVecPoint.fromList([
        [cv.Point(140, 160), cv.Point(470, 140), cv.Point(490, 640), cv.Point(120, 660)],
      ]),
      cv.Scalar(204, 204, 204),
    );
    final expected = const [Pt(140, 160), Pt(470, 140), Pt(490, 640), Pt(120, 660)];
    final luma = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
    final grey = await detector.detectFrame(
      FrameData(bytes: luma.data, width: img.cols, height: img.rows, format: PixelFormat.luma),
    );
    final colour = await detector.detectFrame(yuvFrame(img));
    expect(colour.found, isTrue, reason: 'the colour pass finds it');
    expect(maxCornerError(colour.corners, expected), lessThan(tolerance));
    expect(
      grey.found && maxCornerError(grey.corners, expected) < tolerance,
      isFalse,
      reason: 'brightness alone cannot',
    );
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
