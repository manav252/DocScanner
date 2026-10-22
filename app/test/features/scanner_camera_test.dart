import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/services/camera/scanner_camera.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  // A page in the top-left area of a landscape sensor frame.
  const sensor = [Pt(0.1, 0.1), Pt(0.4, 0.1), Pt(0.4, 0.6), Pt(0.1, 0.6)];

  test('rotation 0 keeps coordinates', () {
    expect(AnalysisFrame(lumaFrame()).toUpright(sensor), sensor);
  });

  test('rotation 90 (typical Android back camera) maps to portrait, re-ordered TL..BL', () {
    final up = AnalysisFrame(lumaFrame(), rotationDegrees: 90).toUpright(sensor);
    // (x, y) -> (1 - y, x)
    expect(up, const [Pt(0.4, 0.1), Pt(0.9, 0.1), Pt(0.9, 0.4), Pt(0.4, 0.4)]);
  });

  test('rotation 180 and 270', () {
    expect(AnalysisFrame(lumaFrame(), rotationDegrees: 180).toUpright(sensor).first.x, closeTo(0.6, 1e-9));
    expect(AnalysisFrame(lumaFrame(), rotationDegrees: 270).toUpright(sensor),
        const [Pt(0.1, 0.6), Pt(0.6, 0.6), Pt(0.6, 0.9), Pt(0.1, 0.9)]);
  });

  test('brightness estimate', () {
    expect(estimateBrightness(lumaFrame(level: 30)), 30);
    expect(estimateBrightness(lumaFrame(level: 200)), 200);
  });
}
