// Auto-capture waits for a sharp frame: shake blurs a photo even while the
// page outline looks steady.
import 'dart:typed_data';

import 'package:docscanner/imaging/scan_engine.dart';
import 'package:docscanner/services/camera/scanner_camera.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 160x120 frame of printed-text-like stripes; [blur] smears it sideways
/// (motion blur) over that many pixels.
FrameData frame({int blur = 1, PixelFormat format = PixelFormat.luma}) {
  const w = 160, h = 120;
  final luma = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0;
      for (var k = 0; k < blur; k++) {
        final xx = (x + k).clamp(0, w - 1);
        sum += ((xx ~/ 3) + (y ~/ 5)).isEven ? 230 : 30;
      }
      luma[y * w + x] = sum ~/ blur;
    }
  }
  if (format == PixelFormat.luma) return FrameData(bytes: luma, width: w, height: h, format: format);
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba.setRange(i * 4, i * 4 + 4, [luma[i], luma[i], luma[i], 255]);
  }
  return FrameData(bytes: rgba, width: w, height: h, format: format);
}

void main() {
  test('motion blur lowers sharpness, for camera (luma) and web (RGBA) frames', () {
    for (final format in [PixelFormat.luma, PixelFormat.rgba]) {
      final sharp = estimateSharpness(frame(format: format));
      final blurred = estimateSharpness(frame(blur: 6, format: format));
      expect(blurred, lessThan(0.5 * sharp), reason: '$format');
    }
  });

  test('the gate lets a sharp frame through, not one blurred by shake', () {
    final gate = SharpnessGate();
    final sharp = estimateSharpness(frame()), blurred = estimateSharpness(frame(blur: 6));
    expect(gate.update(sharp), isTrue);
    expect(gate.update(blurred), isFalse);
    expect(gate.update(sharp), isTrue);
    gate.reset();
    expect(gate.update(blurred), isTrue, reason: 'nothing sharper seen since the reset');
  });

  test('cheap enough for the UI thread: a 640x480 camera frame', () {
    final f = FrameData(bytes: Uint8List(640 * 480), width: 640, height: 480, format: PixelFormat.luma);
    for (var i = 0; i < 5; i++) {
      estimateSharpness(f);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      estimateSharpness(f);
    }
    final ms = sw.elapsedMicroseconds / 50 / 1000;
    // ignore: avoid_print
    print('estimateSharpness 640x480: ${ms.toStringAsFixed(2)} ms');
    expect(ms, lessThan(2));
  });
}
