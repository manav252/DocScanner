import 'dart:async';
import 'dart:typed_data';

import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/page_edits.dart';
import 'package:docscanner/imaging/scan_engine.dart';
import 'package:docscanner/services/camera/scanner_camera.dart';
import 'package:flutter/widgets.dart';

/// Frame of uniform brightness [level] (luma).
FrameData lumaFrame({int w = 64, int h = 48, int level = 128}) =>
    FrameData(bytes: Uint8List(w * h)..fillRange(0, w * h, level), width: w, height: h, format: PixelFormat.luma);

class FakeCamera implements ScannerCamera {
  FakeCamera({this.failure, this.brightness = 128});
  CameraFailure? failure;
  int brightness;
  bool paused = false, disposed = false, torch = false;
  int pictures = 0;
  final photo = Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> initialize() async {
    if (failure != null) throw failure!;
  }

  @override
  double get previewAspectRatio => 0.75;

  @override
  int cameraCount = 1;

  @override
  Widget buildPreview() => const SizedBox.expand();

  @override
  Future<AnalysisFrame> nextFrame() async {
    do {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    } while (paused && !disposed);
    return AnalysisFrame(lumaFrame(level: brightness));
  }

  @override
  Future<CapturedPhoto> takePicture() async {
    pictures++;
    return CapturedPhoto(photo);
  }

  @override
  bool get supportsTorch => true;

  @override
  Future<void> setTorch(bool on) async => torch = on;

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> dispose() async => disposed = true;
}

/// Engine whose live detection is scripted by [frameDetector].
class FakeEngine implements ScanEngine {
  FakeEngine({required this.frameDetector, this.stillDetection, this.stillSize = const (1000, 1400)});

  /// Called for every frame with the frame index.
  Detection Function(int i) frameDetector;
  Detection? stillDetection;
  (int, int) stillSize;
  int frames = 0;
  List<Pt>? warpedCorners;

  @override
  Future<void> get ready async {}

  @override
  Future<Detection> detectFrame(FrameData frame) async => frameDetector(frames++);

  int normalized = 0;

  /// Bytes this engine cannot decode (like a corrupt photo).
  bool Function(Uint8List bytes)? unreadable;

  @override
  Future<NormalizedImage> normalizeEncoded(Uint8List bytes, {int maxSide = 4000, int quality = 92}) async {
    if (unreadable?.call(bytes) ?? false) throw StateError('cannot decode image');
    normalized++;
    return (bytes: bytes, width: stillSize.$1, height: stillSize.$2);
  }

  @override
  Future<EncodedDetection> detectEncoded(Uint8List bytes) async => (
    detection: stillDetection ?? Detection(fullBounds(stillSize.$1, stillSize.$2), found: false),
    width: stillSize.$1,
    height: stillSize.$2,
  );

  @override
  Future<Uint8List> warpEncoded(Uint8List bytes, List<Pt> corners, {int maxSide = 3000, int quality = 92}) async {
    warpedCorners = corners;
    return bytes;
  }

  final processed = <PageEdits>[];

  @override
  Future<Uint8List> processEncoded(Uint8List bytes, PageEdits edits, {int? maxSide, int quality = 90}) async {
    processed.add(edits);
    return bytes;
  }

  @override
  void dispose() {}
}

/// A page covering ~half of a 64x48 frame, optionally shifted.
Detection pageDetection({double dx = 0}) =>
    Detection([Pt(12 + dx, 8), Pt(52 + dx, 8), Pt(52 + dx, 40), Pt(12 + dx, 40)], found: true, score: 0.4);

final noPage = Detection(fullBounds(64, 48), found: false);

/// Polls [condition] in real time.
Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
