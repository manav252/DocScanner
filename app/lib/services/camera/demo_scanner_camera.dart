// A "camera" that plays bundled sample photos. Used when no real camera is
// available (offered on the error screen), for demos, and by tests.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../imaging/scan_engine.dart';
import 'scanner_camera.dart';

class DemoScannerCamera implements ScannerCamera {
  DemoScannerCamera({
    this.samples = const ['tilted_paper', 'low_contrast', 'cluttered_background', 'strong_perspective'],
    AssetBundle? bundle,
    this.frameInterval = const Duration(milliseconds: 33),
  }) : _bundle = bundle ?? rootBundle;

  final List<String> samples;
  final AssetBundle _bundle;
  final Duration frameInterval;

  final _images = <({Uint8List jpeg, FrameData frame})>[];
  final index = ValueNotifier<int>(0);
  bool _paused = false;

  @override
  Future<void> initialize() async {
    for (final name in samples) {
      final jpeg = (await _bundle.load('assets/samples/$name.jpg')).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(jpeg, targetWidth: 480);
      final image = (await codec.getNextFrame()).image;
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      _images.add((
        jpeg: jpeg,
        frame: FrameData(bytes: rgba, width: image.width, height: image.height, format: PixelFormat.rgba),
      ));
      image.dispose();
    }
  }

  /// Show the next sample (simulates pointing the camera at another page).
  void nextSample() => index.value = (index.value + 1) % _images.length;

  @override
  double get previewAspectRatio => _images[index.value].frame.width / _images[index.value].frame.height;

  @override
  Widget buildPreview() => ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (_, i, _) => Image.memory(_images[i].jpeg, fit: BoxFit.fill, gaplessPlayback: true),
      );

  @override
  Future<AnalysisFrame> nextFrame() async {
    do {
      await Future<void>.delayed(frameInterval);
    } while (_paused);
    return AnalysisFrame(_images[index.value].frame);
  }

  @override
  Future<CapturedPhoto> takePicture() async => CapturedPhoto(_images[index.value].jpeg);

  @override
  bool get supportsTorch => false;

  @override
  Future<void> setTorch(bool on) async {}

  @override
  Future<void> pause() async => _paused = true;

  @override
  Future<void> resume() async => _paused = false;

  @override
  Future<void> dispose() async => index.dispose();
}
