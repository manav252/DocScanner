// Browser camera via getUserMedia. Works with a Mac/PC webcam and with phone
// browsers (rear camera preferred). Needs a secure context: https:// or localhost.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../core/crash_note.dart';

import '../../imaging/scan_engine.dart';
import 'scanner_camera.dart';

ScannerCamera createDeviceCamera([int index = 0]) => WebScannerCamera(index);

class WebScannerCamera implements ScannerCamera {
  WebScannerCamera([this.index = 0]);

  /// Which camera to open (0 = the browser's choice, rear camera preferred).
  final int index;

  @override
  int cameraCount = 1;

  /// Analysis frames are downscaled to this longest side (the detector works at 500 px).
  static const analysisMaxSide = 640;

  /// createImageBitmap resizes for us (false once it turned out it does not).
  /// (`?oldgrab=1` in the URL: the previous way, for measurements.)
  bool _bitmapResize = !web.window.location.search.contains('oldgrab=1');

  /// Upper bound on analysis rate (10 per second): enough to follow a page,
  /// and it keeps a phone from heating up (30 per second used more than a
  /// whole CPU core).
  static const minFrameInterval = Duration(milliseconds: 100);

  static var _viewCounter = 0;
  late final String _viewType = 'docscanner-camera-${_viewCounter++}';

  final web.HTMLVideoElement _video = web.HTMLVideoElement();
  web.MediaStream? _stream;
  web.OffscreenCanvas? _analysisCanvas;
  final _sinceLastFrame = Stopwatch();
  bool _paused = false;

  @override
  Future<void> initialize() async {
    if (!web.window.isSecureContext) {
      throw const CameraFailure(CameraFailureKind.unsupported, 'Camera needs HTTPS (or localhost).');
    }
    final devices = web.window.navigator.mediaDevices;
    // Camera names/ids are only listed after permission was granted once.
    final known = index > 0 ? await _videoInputs(devices) : const <web.MediaDeviceInfo>[];
    final constraints = web.MediaStreamConstraints(
      audio: false.toJS,
      video: {
        if (known.isEmpty) 'facingMode': {'ideal': 'environment'},
        if (known.isNotEmpty) 'deviceId': {'exact': known[index % known.length].deviceId},
        'width': {'ideal': 1920},
        'height': {'ideal': 1080},
      }.jsify()!,
    );
    try {
      _stream = await devices.getUserMedia(constraints).toDart;
    } catch (e) {
      final name = _domErrorName(e);
      throw switch (name) {
        'NotAllowedError' || 'SecurityError' => CameraFailure(CameraFailureKind.permissionDenied, name),
        'NotFoundError' || 'OverconstrainedError' => CameraFailure(CameraFailureKind.noCamera, name),
        'NotReadableError' || 'AbortError' => CameraFailure(CameraFailureKind.inUse, name),
        _ => CameraFailure(CameraFailureKind.other, e.toString()),
      };
    }
    _video
      ..autoplay = true
      ..muted = true
      ..playsInline = true
      ..srcObject = _stream
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.pointerEvents = 'none';
    final loaded = Completer<void>();
    void onMeta(web.Event _) => loaded.isCompleted ? null : loaded.complete();
    _video.addEventListener('loadedmetadata', onMeta.toJS);
    await _video.play().toDart;
    if (_video.videoWidth == 0) await loaded.future.timeout(const Duration(seconds: 10));
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);
    try {
      cameraCount = (await _videoInputs(devices)).length.clamp(1, 16);
    } catch (_) {
      cameraCount = 1;
    }
    _sinceLastFrame.start();
  }

  static Future<List<web.MediaDeviceInfo>> _videoInputs(web.MediaDevices devices) async => [
    for (final d in (await devices.enumerateDevices().toDart).toDart)
      if (d.kind == 'videoinput' && d.deviceId.isNotEmpty) d,
  ];

  /// DOMException name from a caught JS error (works under dart2js and dart2wasm).
  static String _domErrorName(Object e) {
    final s = e.toString();
    const names = [
      'NotAllowedError',
      'SecurityError',
      'NotFoundError',
      'OverconstrainedError',
      'NotReadableError',
      'AbortError',
    ];
    return names.firstWhere(s.contains, orElse: () => '');
  }

  @override
  double get previewAspectRatio => _video.videoWidth == 0 ? 4 / 3 : _video.videoWidth / _video.videoHeight;

  @override
  Widget buildPreview() => HtmlElementView(viewType: _viewType);

  @override
  Future<AnalysisFrame> nextFrame() async {
    while (true) {
      final wait = minFrameInterval - _sinceLastFrame.elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!_paused && _video.readyState >= 2 && _video.videoWidth > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _sinceLastFrame.reset();
    final vw = _video.videoWidth, vh = _video.videoHeight;
    final s = math.min(1.0, analysisMaxSide / math.max(vw, vh));
    final w = (vw * s).round(), h = (vh * s).round();
    final canvas = _analysisCanvas != null && _analysisCanvas!.width == w && _analysisCanvas!.height == h
        ? _analysisCanvas!
        : (_analysisCanvas = web.OffscreenCanvas(w, h));
    final ctx = canvas.getContext('2d', {'willReadFrequently': true}.jsify())! as web.OffscreenCanvasRenderingContext2D;
    // Let the browser shrink the frame (off the main thread) and draw the small
    // result: drawing the full camera frame onto a canvas that is read back
    // took ~27% of the main thread while scanning.
    web.ImageBitmap? small;
    if (_bitmapResize) {
      try {
        final bitmap = await web.window
            .createImageBitmap(_video, web.ImageBitmapOptions(resizeWidth: w, resizeHeight: h, resizeQuality: 'low'))
            .toDart;
        if (bitmap.width == w && bitmap.height == h) {
          small = bitmap;
        } else {
          bitmap.close();
          _bitmapResize = false; // resizing not supported: draw the full frame
        }
      } catch (_) {
        _bitmapResize = false;
      }
    }
    if (small != null) {
      ctx.drawImage(small, 0, 0);
      small.close();
    } else {
      ctx.drawImage(_video, 0, 0, w.toDouble(), h.toDouble());
    }
    final data = ctx.getImageData(0, 0, w, h).data.toDart;
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return AnalysisFrame(FrameData(bytes: bytes, width: w, height: h, format: PixelFormat.rgba));
  }

  @override
  Future<CapturedPhoto> takePicture() async {
    final w = _video.videoWidth, h = _video.videoHeight;
    if (w == 0) throw const CameraFailure(CameraFailureKind.other, 'camera not ready');
    final note = noteStep('camera: take photo ${w}x$h');
    final canvas = web.OffscreenCanvas(w, h);
    (canvas.getContext('2d')! as web.OffscreenCanvasRenderingContext2D).drawImage(_video, 0, 0);
    final blob = await canvas.convertToBlob(web.ImageEncodeOptions(type: 'image/jpeg', quality: 0.95)).toDart;
    final buf = await blob.arrayBuffer().toDart;
    noteDone(note);
    return CapturedPhoto(buf.toDart.asUint8List());
  }

  web.MediaStreamTrack? get _track {
    final tracks = _stream?.getVideoTracks().toDart;
    return tracks == null || tracks.isEmpty ? null : tracks.first;
  }

  @override
  bool get supportsTorch {
    final t = _track;
    if (t == null || !t.has('getCapabilities')) return false;
    final caps = t.getCapabilities();
    return caps.has('torch');
  }

  @override
  Future<void> setTorch(bool on) async {
    final t = _track;
    if (t == null) return;
    await t
        .applyConstraints(
          {
                'advanced': [
                  {'torch': on},
                ],
              }.jsify()!
              as web.MediaTrackConstraints,
        )
        .toDart;
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _video.pause();
  }

  @override
  Future<void> resume() async {
    _paused = false;
    await _video.play().toDart;
  }

  @override
  Future<void> dispose() async {
    for (final t in _stream?.getTracks().toDart ?? <web.MediaStreamTrack>[]) {
      t.stop();
    }
    _stream = null;
    _video.srcObject = null;
  }
}
