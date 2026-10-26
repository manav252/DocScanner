// The native (opencv_dart) detector on the hard cases (hand-held, plain white,
// cluttered, half shadow, handwritten, curved, ID cards): it must agree with
// the Python reference (same page found or not; within 6 px wherever the
// reference finds the right corners), and the success rate per
// case is written to docs/testing/detection-after-dart.json.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/page_curves.dart';
import 'package:docscanner/imaging/native/opencv_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'fixtures.dart';

final hardDir = Directory('${fixturesDir.path}/hard');
final hard = jsonDecode(File('${hardDir.path}/hard_cases.json').readAsStringSync()) as Map<String, dynamic>;
final hardReference =
    jsonDecode(File('${hardDir.path}/python_reference.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final results = <String, Map<String, int>>{};
  for (final MapEntry(key: name, value: items as List) in (hard['cases'] as Map<String, dynamic>).entries) {
    test('hard case: $name', () {
      var ok = 0;
      for (final it in items.cast<Map<String, dynamic>>()) {
        final img = cv.imread('${hardDir.path}/${it['file']}');
        final d = detectDocumentMat(img);
        img.dispose();
        final py = hardReference[it['file']] as Map<String, dynamic>;
        expect(d.found, py['found'], reason: '${it['file']}: found differs from the Python reference');
        if (d.found) {
          final truth = orderCorners(cornersOf(it['corners']));
          // Where the reference is right, the port must land on the same corners.
          if (maxCornerError(cornersOf(py['corners']), truth) < tolerance) {
            final diff = maxCornerError(d.corners, cornersOf(py['corners']));
            expect(diff, lessThan(6), reason: '${it['file']} differs from the Python reference by ${diff.round()} px');
          }
          if (maxCornerError(d.corners, truth) < tolerance) ok++;
        }
      }
      results[name] = {'success': ok, 'total': items.length};
    });
  }
  test('curved pages: same edge curves as the reference, and they come out flat', () {
    for (final items in (hard['cases'] as Map<String, dynamic>).values) {
      for (final it in (items as List).cast<Map<String, dynamic>>()) {
        final img = cv.imread('${hardDir.path}/${it['file']}');
        final corners = cornersOf(it['corners']);
        final curves = pageCurvesMat(img, corners);
        final py = (hardReference[it['file']] as Map<String, dynamic>)['curves'] as List?;
        expect(curves == null, py == null, reason: '${it['file']}: curved or not differs from the reference');
        if (curves != null) {
          // Compare the fitted edges along the side (px in the photo).
          for (final (k, c) in [curves.$1, curves.$2].indexed) {
            final ref = [for (final v in py![k] as List) (v as num).toDouble()];
            for (final t in [0.25, 0.5, 0.75]) {
              expect((curveAt(c, t) - curveAt(ref, t)).abs(), lessThan(4), reason: '${it['file']} side $k at $t');
            }
          }
          final flat = warpPageMat(img, corners), plain = warpPerspectiveMat(img, corners);
          expect(ruleBend(plain), greaterThan(2.5), reason: it['file'] as String);
          expect(ruleBend(flat), lessThan(1.0), reason: it['file'] as String);
          flat.dispose();
          plain.dispose();
        }
        img.dispose();
      }
    }
  });

  tearDownAll(() {
    File('../docs/testing/detection-after-dart.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
  });
}

/// How much the red rule under the page title bends (% of the page height).
double ruleBend(cv.Mat bgr) {
  final w = bgr.cols, h = bgr.rows, d = bgr.data;
  final ys = <double>[];
  for (var x = (0.12 * w).toInt(); x < (0.88 * w).toInt(); x += 4) {
    final rows = <int>[];
    for (var y = (0.05 * h).toInt(); y < (0.3 * h).toInt(); y++) {
      final i = (y * w + x) * 3;
      if (d[i + 2] - d[i] > 50 && d[i + 2] > 110) rows.add(y);
    }
    if (rows.isNotEmpty) ys.add(rows[rows.length ~/ 2].toDouble());
  }
  return (ys.reduce(math.max) - ys.reduce(math.min)) / h * 100;
}
