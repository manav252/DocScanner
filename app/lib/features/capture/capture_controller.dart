// State + logic of the live scanner: pulls camera frames, runs detection,
// smooths the outline, decides when to auto-capture, and turns a capture
// into a photo + corners for the corner editor.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../imaging/corner_smoother.dart';
import '../../imaging/geometry.dart';
import '../../imaging/scan_engine.dart' show photoMaxSide;
import '../../services/camera/scanner_camera.dart';

enum CaptureStatus {
  /// Opening the camera / loading OpenCV.
  starting,
  running,
  capturing,

  /// A capture is waiting in [CaptureState.pendingCapture] (corner editor open).
  reviewing,

  /// App in background: camera released.
  suspended,
  failed,
}

/// A captured photo with the page corners to start the corner editor from.
class CaptureResult {
  const CaptureResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.corners,
    required this.detected,
  });
  final Uint8List bytes;
  final int width, height;

  /// TL, TR, BR, BL in photo pixels.
  final List<Pt> corners;

  /// False when nothing was found and [corners] are the full photo bounds.
  final bool detected;
}

/// Auto-capture tuning (overridable in tests).
class CaptureTuning {
  const CaptureTuning({
    this.minDocumentArea = 0.12,
    this.lowLightThreshold = 45,
    this.autoCaptureCooldown = const Duration(milliseconds: 1500),
    this.steadyFrames = 10,
    this.newPageDistance = 0.12,
    this.stillCapture = const Duration(seconds: 4),
    this.stillMotion = 6.0,
  });

  /// Like the Notes app: when no page outline is found (a card held in the
  /// hand, its corners under the fingers) but the camera is held still this
  /// long, the photo is taken anyway; the corners are then fixed by hand.
  final Duration stillCapture;

  /// Mean brightness change between frames (0-255, averaged over a few
  /// frames so one jolt of a hand-held phone does not restart the count)
  /// below which the camera counts as still.
  final double stillMotion;

  /// After a capture, a corner must move this far (fraction of the frame) to
  /// count as a new page and re-arm auto-capture.
  final double newPageDistance;

  /// Ignore "documents" covering less than this fraction of the frame.
  final double minDocumentArea;

  /// Mean frame brightness (0-255) below which we suggest more light / the torch.
  final double lowLightThreshold;

  /// No auto-capture for this long after (re)starting, so the user can aim.
  final Duration autoCaptureCooldown;

  /// Consecutive steady frames needed to auto-capture (~0.8 s at 15 fps).
  final int steadyFrames;
}

final captureTuningProvider = Provider<CaptureTuning>((_) => const CaptureTuning());

const _unset = Object();

/// Snackbar messages from the scanner (the screen shows them in the user's language).
enum CaptureMessage { captureFailed, badPhotoFile, noFlashlight }

class CaptureState {
  const CaptureState({
    this.status = CaptureStatus.starting,
    this.failure,
    this.corners,
    this.steadyProgress = 0,
    this.autoCapture = true,
    this.lowLight = false,
    this.tooSmall = false,
    this.awaitingNextPage = false,
    this.torchOn = false,
    this.supportsTorch = false,
    this.cameraCount = 1,
    this.previewAspectRatio = 3 / 4,
    this.fps = 0,
    this.pendingCapture,
    this.message,
    this.debug,
    this.stillProgress = 0,
    this.blurry = false,
    this.noPageFor = Duration.zero,
  });

  final CaptureStatus status;
  final CameraFailure? failure;

  /// Smoothed page outline in normalised upright-preview coordinates, or null.
  final List<Pt>? corners;

  /// 0..1 while the page is held steady (auto-capture fires at 1).
  final double steadyProgress;
  final bool autoCapture, lowLight, torchOn, supportsTorch;

  /// A page is visible but too small to scan well ("Move closer").
  final bool tooSmall;

  /// The page in view was just captured; auto-capture waits for a new page.
  final bool awaitingNextPage;

  /// Cameras available to switch between (1 = no switch button).
  final int cameraCount;
  final double previewAspectRatio, fps;
  final CaptureResult? pendingCapture;

  /// One-off message for a snackbar (e.g. a failed capture).
  final CaptureMessage? message;

  /// Diagnostics line (web: `?debug=1`): frame rate, page size, steadiness, sharpness.
  final String? debug;

  /// 0..1 while the camera is held still with no page found (captured at 1).
  final double stillProgress;

  /// The last frame was blurred (shake, focusing): it was not searched.
  final bool blurry;

  /// How long no page has been found (for hints after a while).
  final Duration noPageFor;

  bool get documentFound => corners != null;

  CaptureState copyWith({
    CaptureStatus? status,
    Object? failure = _unset,
    Object? corners = _unset,
    double? steadyProgress,
    bool? autoCapture,
    bool? lowLight,
    bool? tooSmall,
    bool? awaitingNextPage,
    bool? torchOn,
    bool? supportsTorch,
    int? cameraCount,
    double? previewAspectRatio,
    double? fps,
    Object? pendingCapture = _unset,
    Object? message = _unset,
    String? debug,
    double? stillProgress,
    bool? blurry,
    Duration? noPageFor,
  }) => CaptureState(
    status: status ?? this.status,
    failure: identical(failure, _unset) ? this.failure : failure as CameraFailure?,
    corners: identical(corners, _unset) ? this.corners : corners as List<Pt>?,
    steadyProgress: steadyProgress ?? this.steadyProgress,
    autoCapture: autoCapture ?? this.autoCapture,
    lowLight: lowLight ?? this.lowLight,
    tooSmall: tooSmall ?? this.tooSmall,
    awaitingNextPage: awaitingNextPage ?? this.awaitingNextPage,
    torchOn: torchOn ?? this.torchOn,
    supportsTorch: supportsTorch ?? this.supportsTorch,
    cameraCount: cameraCount ?? this.cameraCount,
    previewAspectRatio: previewAspectRatio ?? this.previewAspectRatio,
    fps: fps ?? this.fps,
    pendingCapture: identical(pendingCapture, _unset) ? this.pendingCapture : pendingCapture as CaptureResult?,
    message: identical(message, _unset) ? this.message : message as CaptureMessage?,
    debug: debug ?? this.debug,
    stillProgress: stillProgress ?? this.stillProgress,
    blurry: blurry ?? this.blurry,
    noPageFor: noPageFor ?? this.noPageFor,
  );
}

class CaptureController extends Notifier<CaptureState> {
  ScannerCamera? _camera;
  int _generation = 0;
  late CaptureTuning _tuning;
  final _smoother = CornerSmoother();
  late StabilityTracker _stability;
  final _sharpness = SharpnessGate();

  /// Camera-still capture: the previous frame's brightness grid, since when
  /// the camera has been still, and whether that stillness was used already.
  Uint8List? _lastGrid;
  double _motion = 255;
  Duration? _stillSince;
  bool _stillUsed = false;

  /// Steady frames in a row that were not sharp; after [maxSharpWait] the page is captured anyway.
  int _unsharpSteady = 0;

  /// Blurred frames skipped in a row (at most [maxBlurSkips], so a camera whose
  /// frames vary a lot still gets searched), and since when no page is found.
  int _blurSkips = 0;
  static const maxBlurSkips = 3;
  Duration? _noPageSince;
  static const maxSharpWait = 6;

  /// `?debug=1` on the web: show a diagnostics line on the scanner.
  final bool _debug = kIsWeb && Uri.base.queryParameters['debug'] == '1';
  final _brightness = <double>[];
  final _frameTimes = <int>[];
  final _clock = Stopwatch()..start();
  Duration _autoCaptureAllowedAt = Duration.zero;

  /// After a capture, auto-capture stays off until the page is taken away or
  /// changes, so holding the same sheet does not capture it twice.
  List<Pt>? _lastCaptured;
  int _framesWithoutPage = 0;

  /// The open camera (for building the preview).
  ScannerCamera? get camera => _camera;

  @override
  CaptureState build() {
    ref.watch(cameraFactoryProvider); // switching demo/device restarts the scanner
    _tuning = ref.watch(captureTuningProvider);
    _stability = StabilityTracker(window: _tuning.steadyFrames);
    ref.onDispose(_shutdown);
    scheduleMicrotask(_start);
    return const CaptureState();
  }

  Future<void> _start() async {
    final gen = ++_generation;
    _resetTracking();
    final camera = ref.read(cameraFactoryProvider)();
    try {
      await camera.initialize();
      await ref.read(scanEngineProvider).ready;
    } on CameraFailure catch (f) {
      await camera.dispose();
      if (gen == _generation) state = state.copyWith(status: CaptureStatus.failed, failure: f);
      return;
    } catch (e) {
      await camera.dispose();
      if (gen == _generation) {
        state = state.copyWith(status: CaptureStatus.failed, failure: CameraFailure(CameraFailureKind.other, '$e'));
      }
      return;
    }
    if (gen != _generation) {
      await camera.dispose();
      return;
    }
    _camera = camera;
    state = state.copyWith(
      status: CaptureStatus.running,
      failure: null,
      previewAspectRatio: camera.previewAspectRatio,
      supportsTorch: camera.supportsTorch,
      cameraCount: camera.cameraCount,
      torchOn: false,
    );
    unawaited(_loop(gen, camera));
  }

  void _resetTracking() {
    _smoother.reset();
    _stability.reset();
    _sharpness.reset();
    _brightness.clear();
    _frameTimes.clear();
    _autoCaptureAllowedAt = _clock.elapsed + _tuning.autoCaptureCooldown;
  }

  Future<void> _loop(int gen, ScannerCamera camera) async {
    final engine = ref.read(scanEngineProvider);
    while (gen == _generation) {
      final AnalysisFrame frame;
      try {
        frame = await camera.nextFrame();
      } catch (_) {
        if (gen != _generation) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      if (gen != _generation) return;
      if (state.status != CaptureStatus.running) continue;
      final f = frame.data;
      final analysisStart = _clock.elapsed;
      // A blurred frame (shake, focusing) gives a wrong or no outline: skip it
      // and keep the last outline, with a "Hold steady" hint.
      final sharpness = estimateSharpness(f);
      final sharpFrame = _sharpness.update(sharpness);
      if (_sharpness.isBlurry(sharpness) && _blurSkips < maxBlurSkips) {
        _blurSkips++;
        state = state.copyWith(blurry: true);
        continue;
      }
      _blurSkips = 0;
      final detection = await engine
          .detectFrame(f)
          .catchError((Object _) => Detection(fullBounds(f.width, f.height), found: false));
      if (gen != _generation || state.status != CaptureStatus.running) continue;

      final good = detection.found && detection.score >= _tuning.minDocumentArea;
      final upright = good ? frame.toUpright(detection.normalized(f.width, f.height)) : null;
      final smoothed = _smoother.update(upright);
      final steady = _stability.update(upright);
      // Shake blurs the photo even while the outline looks steady: wait for a
      // sharp frame, but not forever (a camera whose frames never count as
      // sharp, e.g. heavy noise reduction, must still capture).
      _unsharpSteady = steady && !sharpFrame ? _unsharpSteady + 1 : 0;
      final sharp = sharpFrame || _unsharpSteady >= maxSharpWait;

      _brightness.add(estimateBrightness(f));
      if (_brightness.length > 15) _brightness.removeAt(0);
      final meanBrightness = _brightness.reduce((a, b) => a + b) / _brightness.length;

      final now = _clock.elapsedMilliseconds;
      _frameTimes.add(now);
      while (_frameTimes.length > 1 && now - _frameTimes.first > 2000) {
        _frameTimes.removeAt(0);
      }
      final fps = _frameTimes.length < 2 ? 0.0 : (_frameTimes.length - 1) * 1000 / math.max(1, now - _frameTimes.first);

      final now0 = _clock.elapsed;
      if (good) {
        _noPageSince = null;
      } else {
        _noPageSince ??= now0;
      }
      state = state.copyWith(
        blurry: false,
        noPageFor: _noPageSince == null ? Duration.zero : now0 - _noPageSince!,
        corners: smoothed,
        steadyProgress: _stability.progress,
        lowLight: _brightness.length >= 5 && meanBrightness < _tuning.lowLightThreshold,
        tooSmall: detection.found && detection.score < _tuning.minDocumentArea,
        fps: fps,
        debug: _debug
            ? 'fps ${fps.toStringAsFixed(0)} · page ${detection.found ? detection.score.toStringAsFixed(2) : '-'}'
                  ' · steady ${(_stability.progress * 100).round()}% · sharp ${sharpFrame ? 'yes' : 'no'}'
                  ' (${sharpness.round()}) · ${f.width}x${f.height}'
            : null,
      );
      // Held still with no page found: count towards a capture anyway.
      final grid = lumaGrid(f);
      if (_lastGrid != null) _motion = 0.7 * math.min(_motion, 64) + 0.3 * gridMotion(grid, _lastGrid!);
      final still = _motion < _tuning.stillMotion;
      _lastGrid = grid;
      if (!still) {
        _stillSince = null;
        _stillUsed = false;
      } else {
        _stillSince ??= _clock.elapsed;
      }
      final stillFor = _stillSince == null ? Duration.zero : _clock.elapsed - _stillSince!;
      final stillCapture = !good && !_stillUsed && stillFor >= _tuning.stillCapture;
      final stillProgress = good || _stillUsed
          ? 0.0
          : (stillFor.inMilliseconds / _tuning.stillCapture.inMilliseconds).clamp(0.0, 1.0);
      if (stillProgress != state.stillProgress) state = state.copyWith(stillProgress: stillProgress);
      _updateArming(upright);
      if (state.awaitingNextPage != (_lastCaptured != null)) {
        state = state.copyWith(awaitingNextPage: _lastCaptured != null);
      }
      if (steady && sharp && state.autoCapture && _lastCaptured == null && _clock.elapsed >= _autoCaptureAllowedAt) {
        await capture();
      } else if (stillCapture && state.autoCapture && _clock.elapsed >= _autoCaptureAllowedAt) {
        _stillUsed = true; // once per stillness: move the camera to scan again
        await capture();
      }
      // A slow phone: rest as long as the analysis took, so the scanner uses
      // at most about half of it and the phone stays cool.
      final spent = _clock.elapsed - analysisStart;
      if (spent > const Duration(milliseconds: 50)) await Future<void>.delayed(spent);
    }
  }

  /// Re-arm auto-capture once the page leaves the view for a moment or a
  /// clearly different page/position appears.
  void _updateArming(List<Pt>? upright) {
    final last = _lastCaptured;
    if (last == null) return;
    if (upright == null) {
      if (++_framesWithoutPage >= 5) _lastCaptured = null;
      return;
    }
    _framesWithoutPage = 0;
    var moved = 0.0;
    for (var i = 0; i < 4; i++) {
      final d = upright[i].distanceTo(last[i]);
      if (d > moved) moved = d;
    }
    if (moved > _tuning.newPageDistance) _lastCaptured = null;
  }

  /// Take a full-resolution photo and find the page in it.
  Future<void> capture() async {
    final camera = _camera;
    if (camera == null || state.status != CaptureStatus.running) return;
    final gen = _generation;
    final previewCorners = state.corners;
    _lastCaptured = previewCorners;
    _framesWithoutPage = 0;
    state = state.copyWith(status: CaptureStatus.capturing);
    unawaited(HapticFeedback.mediumImpact());
    try {
      final photo = await camera.takePicture();
      await camera.pause();
      final engine = ref.read(scanEngineProvider);
      // Upright, size-capped pixels for everything downstream (editor, warp, PDF).
      final upright = await engine.normalizeEncoded(photo.bytes, maxSide: photoMaxSide);
      final r = await engine.detectEncoded(upright.bytes);
      if (gen != _generation) return;
      final List<Pt> corners;
      final bool detected;
      if (r.detection.found) {
        (corners, detected) = (r.detection.corners, true);
      } else if (previewCorners != null) {
        // The still missed the page but the preview had it: reuse the preview outline.
        corners = previewToPhoto(previewCorners, state.previewAspectRatio, r.width, r.height);
        detected = true;
      } else {
        // Nothing found: a box a little inside the photo, easy to drag onto the page.
        (corners, detected) = (defaultQuad(r.width, r.height), false);
      }
      state = state.copyWith(
        status: CaptureStatus.reviewing,
        pendingCapture: CaptureResult(
          bytes: upright.bytes,
          width: r.width,
          height: r.height,
          corners: corners,
          detected: detected,
        ),
      );
    } catch (e) {
      if (gen != _generation) return;
      await camera.resume().catchError((Object _) {});
      _resetTracking();
      state = state.copyWith(status: CaptureStatus.running, message: CaptureMessage.captureFailed);
    }
  }

  /// Status to go back to after reviewing an uploaded photo (the camera may
  /// have failed or be missing: uploading is the fallback).
  CaptureStatus? _beforeUpload;

  /// Use a photo file instead of the camera (desktop without a webcam, or a
  /// photo taken earlier). Opens the same corner review as a capture.
  Future<void> useUploadedPhoto(Uint8List bytes) async {
    if (state.status == CaptureStatus.capturing || state.status == CaptureStatus.reviewing) return;
    _beforeUpload = state.status;
    final wasRunning = state.status == CaptureStatus.running;
    state = state.copyWith(status: CaptureStatus.capturing);
    try {
      if (wasRunning) await _camera?.pause();
      final engine = ref.read(scanEngineProvider);
      await engine.ready;
      final upright = await engine.normalizeEncoded(bytes, maxSide: photoMaxSide);
      final r = await engine.detectEncoded(upright.bytes);
      state = state.copyWith(
        status: CaptureStatus.reviewing,
        pendingCapture: CaptureResult(
          bytes: upright.bytes,
          width: r.width,
          height: r.height,
          corners: r.detection.corners,
          detected: r.detection.found,
        ),
      );
    } catch (e) {
      state = state.copyWith(status: CaptureStatus.reviewing);
      await resume();
      state = state.copyWith(message: CaptureMessage.badPhotoFile);
    }
  }

  /// Back from the corner editor: clear the capture and continue scanning.
  /// [retake]: the capture was discarded, so the same page may be captured again.
  Future<void> resume({bool retake = false}) async {
    if (state.status != CaptureStatus.reviewing) return;
    if (retake) _lastCaptured = null;
    final before = _beforeUpload;
    _beforeUpload = null;
    if (before != null && before != CaptureStatus.running) {
      // No live camera to go back to: return to the failure/start screen.
      state = state.copyWith(status: before, pendingCapture: null);
      return;
    }
    _resetTracking();
    state = state.copyWith(status: CaptureStatus.running, pendingCapture: null, corners: null, steadyProgress: 0);
    await _camera?.resume();
  }

  void clearMessage() => state = state.copyWith(message: null);

  /// Open the next camera (the scanner restarts with it).
  void switchCamera() => ref.read(cameraIndexProvider.notifier).next(state.cameraCount);

  void setAutoCapture(bool on) {
    _autoCaptureAllowedAt = _clock.elapsed + _tuning.autoCaptureCooldown;
    state = state.copyWith(autoCapture: on);
  }

  Future<void> setTorch(bool on) async {
    try {
      await _camera?.setTorch(on);
      state = state.copyWith(torchOn: on);
    } catch (_) {
      state = state.copyWith(supportsTorch: false, message: CaptureMessage.noFlashlight);
    }
  }

  /// App went to the background: release the camera.
  Future<void> suspend() async {
    if (state.status == CaptureStatus.reviewing || state.status == CaptureStatus.failed) return;
    _generation++;
    final c = _camera;
    _camera = null;
    state = state.copyWith(status: CaptureStatus.suspended, corners: null, torchOn: false);
    await c?.dispose();
  }

  /// App back in the foreground (or "Try again" after a failure).
  Future<void> restart() async {
    if (state.status != CaptureStatus.suspended && state.status != CaptureStatus.failed) return;
    state = state.copyWith(status: CaptureStatus.starting, failure: null);
    await _start();
  }

  void _shutdown() {
    _generation++;
    final c = _camera;
    _camera = null;
    c?.dispose();
  }
}

final captureControllerProvider = NotifierProvider.autoDispose<CaptureController, CaptureState>(CaptureController.new);

/// Normalised preview corners -> photo pixels. On Android the preview stream
/// (16:9) and the photo (4:3) have different shapes: the stream is the middle
/// of the sensor's picture, so the photo shows more at the sides (or top and
/// bottom). [previewAspect] and the photo are both upright (width / height).
List<Pt> previewToPhoto(List<Pt> normalized, double previewAspect, int photoWidth, int photoHeight) {
  final photoAspect = photoWidth / photoHeight;
  // Part of the photo's width and height the preview covers (centred).
  final fw = previewAspect < photoAspect ? previewAspect / photoAspect : 1.0;
  final fh = previewAspect > photoAspect ? photoAspect / previewAspect : 1.0;
  return [
    for (final p in normalized)
      Pt(
        ((0.5 + (p.x - 0.5) * fw) * (photoWidth - 1)).clamp(0, photoWidth - 1).toDouble(),
        ((0.5 + (p.y - 0.5) * fh) * (photoHeight - 1)).clamp(0, photoHeight - 1).toDouble(),
      ),
  ];
}

/// Corners for a photo where no page was found: 8 % in from each edge.
List<Pt> defaultQuad(int w, int h) {
  final x0 = 0.08 * (w - 1), y0 = 0.08 * (h - 1), x1 = 0.92 * (w - 1), y1 = 0.92 * (h - 1);
  return [Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)];
}
