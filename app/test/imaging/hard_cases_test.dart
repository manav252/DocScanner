// The native (opencv_dart) detector on the hard cases (hand-held, plain white,
// cluttered, half shadow, handwritten, curved, ID cards): it must agree with
// the Python reference (same page found or not; within 6 px wherever the
// reference finds the right corners), and the success rate per
// case is written to docs/testing/detection-after-dart.json.
import 'dart:convert';
import 'dart:io';

import 'package:docscanner/imaging/geometry.dart';
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
  tearDownAll(() {
    File('../docs/testing/detection-after-dart.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
  });
}
