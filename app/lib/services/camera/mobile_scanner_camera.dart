// Android/iOS camera via the `camera` plugin.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../imaging/scan_engine.dart';
import 'scanner_camera.dart';

ScannerCamera createDeviceCamera([int index = 0]) => MobileScannerCamera(index);

class MobileScannerCamera implements ScannerCamera {
  MobileScannerCamera([this.index = 0]);

  /// Which camera to open: rear cameras first, then the others.
  final int index;
  bool _front = false;

  @override
  int cameraCount = 1;

  CameraController? _controller;
  Completer<AnalysisFrame>? _waiter;
  bool _streaming = false;

  CameraController get _c => _controller ?? (throw StateError('camera not initialised'));

  @override
  Future<void> initialize() async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw _map(e);
    }
    if (cameras.isEmpty) throw const CameraFailure(CameraFailureKind.noCamera);
    final ordered = [
      ...cameras.where((c) => c.lensDirection == CameraLensDirection.back),
      ...cameras.where((c) => c.lensDirection != CameraLensDirection.back),
    ];
    cameraCount = ordered.length;
    final chosen = ordered[index % ordered.length];
    _front = chosen.lensDirection == CameraLensDirection.front;
    final controller = CameraController(
      chosen,
      // 720p stream: plenty for detection (it downsamples to 500 px) and keeps
      // frame conversion cheap. takePicture still returns full sensor resolution.
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw _map(e);
    }
    _controller = controller;
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await controller.setFlashMode(FlashMode.off);
    try {
      await controller.setFocusMode(FocusMode.auto);
    } on CameraException {
      // Fixed-focus cameras.
    }
    await _startStream();
  }

  CameraFailure _map(CameraException e) => switch (e.code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' => CameraFailure(CameraFailureKind.permissionDenied, e.description ?? ''),
    _ => CameraFailure(CameraFailureKind.other, '${e.code}: ${e.description}'),
  };

  Future<void> _startStream() async {
    if (_streaming) return;
    await _c.startImageStream(_onImage);
    _streaming = true;
  }

  void _onImage(CameraImage img) {
    final w = _waiter;
    if (w == null || w.isCompleted) return; // nobody waiting: drop the frame
    _waiter = null;
    final plane = img.planes.first; // Y plane (Android) or the BGRA plane (iOS)
    final frame = FrameData(
      bytes: plane.bytes,
      width: img.width,
      height: img.height,
      rowStride: plane.bytesPerRow,
      format: img.format.group == ImageFormatGroup.bgra8888 ? PixelFormat.bgra : PixelFormat.luma,
    );
    // The UI is locked to portrait. Stream buffers come in sensor orientation
    // (landscape on almost every phone), so rotate them by the sensor angle.
    final rotation = img.width > img.height ? _c.description.sensorOrientation : 0;
    w.complete(AnalysisFrame(frame, rotationDegrees: rotation));
  }

  @override
  double get previewAspectRatio {
    final size = _c.value.previewSize;
    if (size == null) return 3 / 4;
    final long = size.longestSide, short = size.shortestSide;
    return short / long; // portrait
  }

  @override
  // The plugin mirrors the front camera's preview but not its frames; un-mirror
  // so the outline lines up (and text on the page reads the right way round).
  Widget buildPreview() => _front
      ? Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: CameraPreview(_c))
      : CameraPreview(_c);

  @override
  Future<AnalysisFrame> nextFrame() => (_waiter ??= Completer<AnalysisFrame>()).future;

  @override
  Future<CapturedPhoto> takePicture() async {
    try {
      final file = await _c.takePicture();
      return CapturedPhoto(await file.readAsBytes());
    } on CameraException catch (e) {
      throw _map(e);
    }
  }

  @override
  bool get supportsTorch => true; // setTorch reports failure on devices without a flash

  @override
  Future<void> setTorch(bool on) => _c.setFlashMode(on ? FlashMode.torch : FlashMode.off);

  @override
  Future<void> pause() async {
    if (_streaming) {
      await _c.stopImageStream();
      _streaming = false;
    }
    await _c.pausePreview();
  }

  @override
  Future<void> resume() async {
    await _c.resumePreview();
    await _startStream();
  }

  @override
  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    _waiter = null;
    if (c != null) {
      if (_streaming) await c.stopImageStream().catchError((_) {});
      _streaming = false;
      await c.dispose();
    }
  }
}
