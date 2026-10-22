import 'package:docscanner/core/providers.dart';
import 'package:docscanner/features/capture/capture_controller.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/services/camera/scanner_camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // HapticFeedback channel

  late FakeCamera camera;
  late FakeEngine engine;
  late ProviderContainer container;

  ProviderContainer makeContainer({Duration cooldown = Duration.zero}) {
    final c = ProviderContainer(overrides: [
      scanEngineProvider.overrideWithValue(engine),
      cameraFactoryProvider.overrideWithValue(() => camera),
      captureTuningProvider.overrideWithValue(CaptureTuning(autoCaptureCooldown: cooldown, steadyFrames: 5)),
    ]);
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive.
    c.listen(captureControllerProvider, (_, _) {});
    return c;
  }

  CaptureState read() => container.read(captureControllerProvider);
  CaptureController ctrl() => container.read(captureControllerProvider.notifier);

  setUp(() {
    camera = FakeCamera();
    engine = FakeEngine(frameDetector: (_) => pageDetection());
  });

  test('a steady page is auto-captured exactly once', () async {
    engine.stillDetection = Detection(const [Pt(10, 10), Pt(900, 20), Pt(890, 1300), Pt(20, 1290)], found: true, score: .8);
    container = makeContainer();
    await waitFor(() => read().status == CaptureStatus.reviewing);
    final cap = read().pendingCapture!;
    expect(cap.detected, isTrue);
    expect(cap.corners.first, const Pt(10, 10));
    expect((cap.width, cap.height), (1000, 1400));
    expect(camera.pictures, 1);
    expect(camera.paused, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(camera.pictures, 1, reason: 'no second capture while reviewing');
  });

  test('a moving page is not auto-captured', () async {
    engine.frameDetector = (i) => pageDetection(dx: (i % 2) * 6.0);
    container = makeContainer();
    await waitFor(() => engine.frames > 30);
    expect(read().documentFound, isTrue);
    expect(camera.pictures, 0);
  });

  test('auto-capture off: steady page waits for the shutter', () async {
    container = makeContainer();
    await waitFor(() => read().status == CaptureStatus.running);
    ctrl().setAutoCapture(false);
    await waitFor(() => engine.frames > 20);
    expect(camera.pictures, 0);
    await ctrl().capture();
    expect(read().status, CaptureStatus.reviewing);
  });

  test('tiny detections are ignored', () async {
    engine.frameDetector = (_) => Detection(pageDetection().corners, found: true, score: 0.05);
    container = makeContainer();
    await waitFor(() => engine.frames > 20);
    expect(read().documentFound, isFalse);
    expect(camera.pictures, 0);
  });

  test('no page in the still: falls back to the preview outline', () async {
    container = makeContainer();
    await waitFor(() => read().status == CaptureStatus.reviewing);
    final cap = read().pendingCapture!;
    expect(cap.detected, isTrue);
    // Preview page spans x 12..52 of 64 -> ~0.19..0.81 of the still width.
    expect(cap.corners.first.x / cap.width, closeTo(12 / 64, 0.02));
  });

  test('nothing found anywhere: full photo bounds, detected=false', () async {
    engine.frameDetector = (_) => noPage;
    container = makeContainer();
    await waitFor(() => read().status == CaptureStatus.running);
    await ctrl().capture();
    final cap = read().pendingCapture!;
    expect(cap.detected, isFalse);
    expect(cap.corners, fullBounds(1000, 1400));
  });

  test('resume clears the capture and keeps scanning', () async {
    container = makeContainer(cooldown: const Duration(seconds: 10));
    await waitFor(() => read().status == CaptureStatus.running);
    await ctrl().capture();
    await ctrl().resume();
    expect(read().status, CaptureStatus.running);
    expect(read().pendingCapture, isNull);
    expect(camera.paused, isFalse);
    final before = engine.frames;
    await waitFor(() => engine.frames > before + 10);
    expect(camera.pictures, 1, reason: 'cooldown blocks an immediate re-capture');
  });

  test('low light is reported', () async {
    camera.brightness = 20;
    engine.frameDetector = (_) => noPage;
    container = makeContainer();
    await waitFor(() => read().lowLight);
    camera.brightness = 150;
    await waitFor(() => !read().lowLight);
  });

  test('permission denied -> failed state; restart recovers', () async {
    camera.failure = const CameraFailure(CameraFailureKind.permissionDenied);
    container = makeContainer();
    await waitFor(() => read().status == CaptureStatus.failed);
    expect(read().failure!.kind, CameraFailureKind.permissionDenied);
    camera.failure = null;
    await ctrl().restart();
    expect(read().status, isNot(CaptureStatus.failed));
    await waitFor(() => read().status == CaptureStatus.reviewing || read().status == CaptureStatus.running);
  });

  test('suspend releases the camera', () async {
    container = makeContainer(cooldown: const Duration(seconds: 10));
    await waitFor(() => read().status == CaptureStatus.running);
    await ctrl().suspend();
    expect(read().status, CaptureStatus.suspended);
    expect(camera.disposed, isTrue);
  });

  test('torch toggles on the camera', () async {
    container = makeContainer(cooldown: const Duration(seconds: 10));
    await waitFor(() => read().status == CaptureStatus.running);
    await ctrl().setTorch(true);
    expect(camera.torch, isTrue);
    expect(read().torchOn, isTrue);
  });

  test('the same page is not auto-captured twice; removing it re-arms', () async {
    var showPage = true;
    engine.frameDetector = (_) => showPage ? pageDetection() : noPage;
    container = makeContainer();
    await waitFor(() => read().status == CaptureStatus.reviewing);
    await ctrl().resume();
    final before = engine.frames;
    await waitFor(() => engine.frames > before + 20);
    expect(camera.pictures, 1, reason: 'same page still in view');
    showPage = false;
    await waitFor(() => engine.frames > before + 30);
    showPage = true;
    await waitFor(() => read().status == CaptureStatus.reviewing);
    expect(camera.pictures, 2);
  });

  test('a clearly moved page re-arms auto-capture', () async {
    var dx = 0.0;
    engine.frameDetector = (_) => pageDetection(dx: dx);
    container = makeContainer();
    await waitFor(() => read().status == CaptureStatus.reviewing);
    await ctrl().resume();
    dx = 12; // ~19% of the 64 px frame
    await waitFor(() => read().status == CaptureStatus.reviewing);
    expect(camera.pictures, 2);
  });
}
