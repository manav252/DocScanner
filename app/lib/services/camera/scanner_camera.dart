// Camera abstraction used by the scanner screen.
//
//   Android / iOS : `camera` plugin, YUV (Android) or BGRA (iOS) image stream
//   Web           : getUserMedia + <video>, frames grabbed through a canvas
//   Demo          : plays bundled sample photos (any platform; used by tests
//                   and as a fallback when no camera is available)
//
// The scanner pulls frames with [ScannerCamera.nextFrame] only when it is
// ready for one, so slow devices drop frames instead of queueing them.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../imaging/geometry.dart';
import '../../imaging/scan_engine.dart';
import 'unsupported_camera.dart'
    if (dart.library.js_interop) 'web_scanner_camera.dart'
    if (dart.library.io) 'mobile_scanner_camera.dart';

/// A frame for analysis plus how to rotate it to match the on-screen preview.
class AnalysisFrame {
  const AnalysisFrame(this.data, {this.rotationDegrees = 0});
  final FrameData data;

  /// Clockwise rotation (0/90/180/270) that turns the frame upright.
  final int rotationDegrees;

  /// Map normalised frame coordinates to normalised upright-preview coordinates.
  List<Pt> toUpright(List<Pt> normalized) => orderCorners([
    for (final p in normalized)
      switch (rotationDegrees % 360) {
        90 => Pt(1 - p.y, p.x),
        180 => Pt(1 - p.x, 1 - p.y),
        270 => Pt(p.y, 1 - p.x),
        _ => p,
      },
  ]);
}

/// A full-resolution still (JPEG), already upright.
class CapturedPhoto {
  const CapturedPhoto(this.bytes);
  final Uint8List bytes;
}

enum CameraFailureKind {
  /// The user said no (or it was denied before).
  permissionDenied,

  /// No camera on this device / browser.
  noCamera,

  /// Another app or tab is using the camera.
  inUse,

  /// The browser blocks cameras on non-HTTPS pages, or the platform lacks support.
  unsupported,
  other,
}

class CameraFailure implements Exception {
  const CameraFailure(this.kind, [this.message = '']);
  final CameraFailureKind kind;
  final String message;

  @override
  String toString() => 'CameraFailure(${kind.name}${message.isEmpty ? '' : ': $message'})';
}

abstract interface class ScannerCamera {
  /// The device camera for this platform; [index] picks among several
  /// cameras (0 = the default: rear camera on phones).
  factory ScannerCamera.device({int index = 0}) => createDeviceCamera(index);

  /// Opens the camera. Throws [CameraFailure].
  Future<void> initialize();

  /// Width / height of the upright preview.
  double get previewAspectRatio;

  /// The live preview; fills a box of [previewAspectRatio].
  Widget buildPreview();

  /// Completes with the next frame produced after the call.
  Future<AnalysisFrame> nextFrame();

  /// Full-resolution capture.
  Future<CapturedPhoto> takePicture();

  /// How many cameras can be switched between (known after [initialize]).
  int get cameraCount;

  bool get supportsTorch;
  Future<void> setTorch(bool on);

  /// Stop/restart the preview (e.g. while the corner editor is open).
  Future<void> pause();
  Future<void> resume();

  Future<void> dispose();
}

/// Mean brightness (0-255) of a frame, sampled sparsely; used for the low-light hint.
double estimateBrightness(FrameData f) {
  const step = 8;
  var sum = 0, n = 0;
  final bpp = f.format == PixelFormat.luma ? 1 : 4;
  for (var y = 0; y < f.height; y += step) {
    final row = y * f.rowStride;
    for (var x = 0; x < f.width; x += step) {
      final i = row + x * bpp;
      if (bpp == 1) {
        sum += f.bytes[i];
      } else {
        // Channel order does not matter much for a brightness estimate.
        sum += (f.bytes[i] + 2 * f.bytes[i + 1] + f.bytes[i + 2]) >> 2;
      }
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// How sharp [f] is: the variance of the Laplacian (4-neighbour) of its
/// brightness, sampled every third pixel over the central 60% of the frame
/// (where the page is; ~12k samples on a 640x480 frame, cheap enough for the
/// UI thread). Motion blur and missed focus lower it. Only meaningful relative
/// to other frames of the same scene.
double estimateSharpness(FrameData f) {
  const step = 3;
  final bpp = f.format == PixelFormat.luma ? 1 : 4;
  int lum(int x, int y) {
    final i = y * f.rowStride + x * bpp;
    return bpp == 1 ? f.bytes[i] : (f.bytes[i] + 2 * f.bytes[i + 1] + f.bytes[i + 2]) >> 2;
  }

  var sum = 0.0, sumSq = 0.0;
  var n = 0;
  final x0 = math.max(1, f.width ~/ 5), x1 = math.min(f.width - 1, f.width - f.width ~/ 5);
  final y0 = math.max(1, f.height ~/ 5), y1 = math.min(f.height - 1, f.height - f.height ~/ 5);
  for (var y = y0; y < y1; y += step) {
    for (var x = x0; x < x1; x += step) {
      final l = (4 * lum(x, y) - lum(x - 1, y) - lum(x + 1, y) - lum(x, y - 1) - lum(x, y + 1)).toDouble();
      sum += l;
      sumSq += l * l;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

/// Lets auto-capture through only on a sharp frame: at least [ratio] of the
/// sharpest of the last [window] frames (absolute sharpness depends on the
/// scene, so it is compared with the camera's own recent best).
class SharpnessGate {
  SharpnessGate({this.window = 30, this.ratio = 0.6});
  final int window;
  final double ratio;
  final _recent = <double>[];

  /// Add the latest frame's sharpness; true if that frame is sharp enough.
  bool update(double sharpness) {
    _recent.add(sharpness);
    if (_recent.length > window) _recent.removeAt(0);
    return sharpness >= ratio * _recent.reduce((a, b) => a > b ? a : b);
  }

  void reset() => _recent.clear();
}

/// The frame's brightness on a coarse 32x32 grid, to tell whether the camera
/// is held still (see [gridMotion]).
Uint8List lumaGrid(FrameData f) {
  const n = 32;
  final bpp = f.format == PixelFormat.luma ? 1 : 4;
  final out = Uint8List(n * n);
  for (var gy = 0; gy < n; gy++) {
    final y = (gy + 0.5) * f.height ~/ n;
    for (var gx = 0; gx < n; gx++) {
      final x = (gx + 0.5) * f.width ~/ n;
      final i = y * f.rowStride + x * bpp;
      out[gy * n + gx] = bpp == 1 ? f.bytes[i] : (f.bytes[i] + 2 * f.bytes[i + 1] + f.bytes[i + 2]) >> 2;
    }
  }
  return out;
}

/// Mean brightness change (0-255) between two [lumaGrid]s: small when the
/// camera is held still.
double gridMotion(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}
