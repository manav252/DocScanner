// Camera abstraction used by the scanner screen.
//
//   Android / iOS : `camera` plugin, YUV (Android) or BGRA (iOS) image stream
//   Web           : getUserMedia + <video>, frames grabbed through a canvas
//   Demo          : plays bundled sample photos (any platform; used by tests
//                   and as a fallback when no camera is available)
//
// The scanner pulls frames with [ScannerCamera.nextFrame] only when it is
// ready for one, so slow devices drop frames instead of queueing them.
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
