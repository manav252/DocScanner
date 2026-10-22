// Runs the native (opencv_dart) detector on the host against the shared fixtures.
import 'dart:typed_data';

import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/native/opencv_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'fixtures.dart';

cv.Mat load(String name) => cv.imread('${fixturesDir.path}/$name.jpg');

void main() {
  for (final MapEntry(key: name, value: c as Map<String, dynamic>) in cases.entries) {
    test('fixture $name', () {
      final d = detectDocumentMat(load(name));
      expect(d.found, c['found'], reason: c['note'] as String);
      if (c['found'] as bool) {
        final err = maxCornerError(d.corners, cornersOf(c['corners']));
        expect(err, lessThan(tolerance), reason: '$name corner error ${err.toStringAsFixed(1)}px');
        final py = maxCornerError(d.corners, cornersOf((pythonReference[name] as Map)['corners']));
        expect(py, lessThan(6), reason: '$name differs from the Python reference by ${py.toStringAsFixed(1)}px');
      } else {
        expect(d.corners, fullBounds(imageWidth, imageHeight));
      }
    });
  }

  test('luma (camera Y plane) path matches the colour path', () {
    final img = load('tilted_paper');
    final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
    // Simulate a camera buffer with row padding.
    const stride = 1216;
    final buf = Uint8List(stride * gray.rows);
    for (var r = 0; r < gray.rows; r++) {
      buf.setRange(r * stride, r * stride + gray.cols, gray.data, r * gray.cols);
    }
    final a = detectDocumentLuma(buf, gray.cols, gray.rows, rowStride: stride);
    final b = detectDocumentMat(img);
    expect(a.found, isTrue);
    expect(maxCornerError(a.corners, b.corners), lessThan(1.0));
  });

  test('encoded bytes path', () {
    final bytes = Uint8List.fromList(cv.imencode('.jpg', load('strong_perspective')).$2);
    expect(detectDocumentBytes(bytes).found, isTrue);
    expect(() => detectDocumentBytes(Uint8List.fromList([1, 2, 3])), throwsArgumentError);
  });

  test('blank frame falls back to the full bounds', () {
    final m = cv.Mat.zeros(480, 640, cv.MatType.CV_8UC3);
    final d = detectDocumentMat(m);
    expect(d.found, isFalse);
    expect(d.corners, fullBounds(640, 480));
  });

  test('warp produces a page-shaped image, capped by maxSide', () {
    final out = warpPerspectiveMat(load('tilted_paper'), cornersOf((cases['tilted_paper'] as Map)['corners']), maxSide: 800);
    expect([out.rows, out.cols].reduce((a, b) => a > b ? a : b), 800);
    expect(out.cols / out.rows, inInclusiveRange(0.65, 0.85));
  });

  test('speed on a 720x1280 frame', () {
    final frame = cv.resize(load('cluttered_background'), (720, 1280));
    detectDocumentMat(frame);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      detectDocumentMat(frame);
    }
    final ms = sw.elapsedMicroseconds / 20 / 1000;
    // ignore: avoid_print
    print('detectDocumentMat 720x1280 (opencv_dart, host): ${ms.toStringAsFixed(1)} ms');
    expect(ms, lessThan(40));
  });
}
