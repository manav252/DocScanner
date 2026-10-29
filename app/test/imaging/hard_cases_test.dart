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
import 'package:docscanner/imaging/native/opencv_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'fixtures.dart';

final hardDir = Directory('${fixturesDir.path}/hard');
final hard = jsonDecode(File('${hardDir.path}/hard_cases.json').readAsStringSync()) as Map<String, dynamic>;
final hardReference =
    jsonDecode(File('${hardDir.path}/python_reference.json').readAsStringSync()) as Map<String, dynamic>;

final scenesDir = Directory('${fixturesDir.path}/scenes');
final scenes = jsonDecode(File('${scenesDir.path}/scene_cases.json').readAsStringSync()) as Map<String, dynamic>;
final scenesReference =
    jsonDecode(File('${scenesDir.path}/python_reference.json').readAsStringSync()) as Map<String, dynamic>;

/// Parity with the Python reference: the same decision (page found or not) and
/// corners within 6 px. A photo may differ when both results are right (within
/// tolerance of the truth; at most 5 % of photos, checked at the end) or both
/// wrong (listed); one right and the other wrong fails at once. (See
/// test_js/scanner.test.js; both read the JPEGs with libjpeg here.)
final parityDiffers = <String>[];
var parityPhotos = 0;
void checkParity(String file, Detection d, Map<String, dynamic> py, List<Pt> truth) {
  parityPhotos++;
  final pyFound = py['found'] as bool, pyCorners = cornersOf(py['corners']);
  bool right(bool found, List<Pt> c) => found && maxCornerError(c, truth) < tolerance;
  final same = d.found == pyFound && (!d.found || maxCornerError(d.corners, pyCorners) < 6);
  if (same) return;
  final why = d.found != pyFound
      ? 'found differs'
      : 'corners differ by ${maxCornerError(d.corners, pyCorners).toStringAsFixed(1)}px';
  final r = right(d.found, d.corners);
  expect(r, right(pyFound, pyCorners), reason: '$file: $why from the Python reference, and only one of them is right');
  parityDiffers.add('$file ($why; both ${r ? 'right' : 'wrong'})');
}

void main() {
  final results = <String, Map<String, int>>{};
  final sceneResults = <String, Map<String, int>>{};
  for (final MapEntry(key: name, value: items as List) in (scenes['cases'] as Map<String, dynamic>).entries) {
    test('scene: $name', () {
      var ok = 0;
      for (final it in items.cast<Map<String, dynamic>>()) {
        final img = cv.imread('${scenesDir.path}/${it['file']}');
        final d = detectDocumentMat(img);
        img.dispose();
        final truth = orderCorners(cornersOf(it['corners']));
        checkParity(it['file'] as String, d, scenesReference[it['file']] as Map<String, dynamic>, truth);
        if (d.found && maxCornerError(d.corners, truth) < tolerance) ok++;
      }
      sceneResults[name] = {'success': ok, 'total': items.length};
    });
  }
  for (final MapEntry(key: name, value: items as List) in (hard['cases'] as Map<String, dynamic>).entries) {
    test('hard case: $name', () {
      var ok = 0;
      for (final it in items.cast<Map<String, dynamic>>()) {
        final img = cv.imread('${hardDir.path}/${it['file']}');
        final d = detectDocumentMat(img);
        img.dispose();
        final truth = orderCorners(cornersOf(it['corners']));
        checkParity(it['file'] as String, d, hardReference[it['file']] as Map<String, dynamic>, truth);
        if (d.found && maxCornerError(d.corners, truth) < tolerance) ok++;
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

  test('ID card B&W keeps the photo and signature strip grey (PAN cards); ordinary pages unchanged', () {
    final cards = (hard['cases'] as Map<String, dynamic>)['pan'] as List;
    for (final it in cards.cast<Map<String, dynamic>>()) {
      final img = cv.imread('${hardDir.path}/${it['file']}');
      final flat = warpPageMat(img, cornersOf(it['corners']));
      final w = flat.cols, h = flat.rows;
      int levels(cv.Mat m) {
        final seen = <int>{};
        for (var y = (160 * h / 638).toInt(); y < (420 * h / 638).toInt(); y++) {
          for (var x = (50 * w / 1012).toInt(); x < (250 * w / 1012).toInt(); x++) {
            seen.add(m.data[y * w + x]);
          }
        }
        return seen.length;
      }

      final plain = blackAndWhite(flat), kept = blackAndWhite(flat, keepPhoto: true);
      expect(levels(plain), lessThanOrEqualTo(2), reason: it['file'] as String);
      expect(levels(kept), greaterThan(20), reason: it['file'] as String);
      for (final m in [img, flat, plain, kept]) {
        m.dispose();
      }
    }
    for (final name in ['plain_white', 'handwritten']) {
      for (final it in ((hard['cases'] as Map<String, dynamic>)[name] as List).cast<Map<String, dynamic>>()) {
        final img = cv.imread('${hardDir.path}/${it['file']}');
        final flat = warpPageMat(img, cornersOf(it['corners']));
        final g = cv.cvtColor(flat, cv.COLOR_BGR2GRAY);
        expect(findPhotoStrip(g), isNull, reason: it['file'] as String);
        for (final m in [img, flat, g]) {
          m.dispose();
        }
      }
    }
  });

  test('parity: no more than 5 % of photos differ from the Python reference while both are right', () {
    if (parityDiffers.isNotEmpty) {
      // ignore: avoid_print
      print('differ (${parityDiffers.length}/$parityPhotos): ${parityDiffers.join(', ')}');
    }
    expect(parityPhotos, greaterThan(0));
    expect(parityDiffers.where((d) => d.endsWith('both right)')).length, lessThanOrEqualTo(0.05 * parityPhotos));
  });
  tearDownAll(() {
    File('../docs/testing/detection-after-dart.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
    File('../docs/testing/scenes-after-dart.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(sceneResults));
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
