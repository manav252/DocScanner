// Live scanner: camera preview + detected outline, auto/manual capture.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/models.dart';
import '../../services/camera/demo_scanner_camera.dart';
import '../../services/camera/scanner_camera.dart';
import '../common/page_image.dart';
import '../corners/corner_adjust_page.dart';
import '../diagnostics/detector_diagnostics_page.dart';
import '../editor/document_controller.dart';
import '../editor/document_editor_page.dart';
import '../library/library_controller.dart';
import 'capture_controller.dart';
import 'widgets/live_quad_overlay.dart';
import 'scan_guidance.dart';
import 'widgets/shutter_button.dart';

class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key, this.documentId, this.replacePageId});

  /// Add pages to this document; null starts a new document on the first capture.
  final String? documentId;

  /// Retake: replace this page of [documentId], then close (pops `true`).
  final String? replacePageId;

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage> with WidgetsBindingObserver {
  late String? _docId = widget.documentId;
  ProviderSubscription<AsyncValue<ScanDocument>>? _docSub;
  late final _repo = ref.read(documentRepositoryProvider);

  /// A document this screen created (deleted again if it ends up empty).
  String? _createdId;

  /// Pages still being processed in the background.
  int _saving = 0;

  bool get _replacing => widget.replacePageId != null;

  void _keepDocumentAlive(String id) {
    _docSub?.close();
    _docSub = ref.listenManual(documentProvider(id), (_, _) {});
  }

  late final CameraActive _camera;

  @override
  void initState() {
    super.initState();
    _repo; // capture before dispose, where ref may no longer be used
    if (_docId != null) _keepDocumentAlive(_docId!);
    _camera = ref.read(cameraActiveProvider.notifier);
    Future.microtask(() => _camera.active = true);
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    final created = _createdId;
    if (created != null && _saving == 0) {
      final repo = _repo;
      repo.get(created).then((d) => d != null && d.pages.isEmpty ? repo.delete(d) : null);
    }
    _docSub?.close();
    Future.microtask(() => _camera.active = false);
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb) SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (kIsWeb) return; // browsers keep the stream; nothing to release
    final c = ref.read(captureControllerProvider.notifier);
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) c.suspend();
    if (s == AppLifecycleState.resumed) c.restart();
  }

  Future<void> _openEditor(CaptureResult capture) async {
    final l = context.l10n;
    final result = await Navigator.of(context).push<CornerAdjustResult>(
      MaterialPageRoute(
        builder: (_) => CornerAdjustPage(
          bytes: capture.bytes,
          width: capture.width,
          height: capture.height,
          corners: capture.corners,
          detected: capture.detected,
          cancelLabel: l.retake,
          confirmLabel: _replacing ? l.replacePage : l.keepScan,
        ),
      ),
    );
    if (!mounted) return;
    final controller = ref.read(captureControllerProvider.notifier);
    if (result == null) {
      await controller.resume(retake: true);
      return;
    }
    if (_replacing) {
      setState(() => _saving++);
      try {
        await ref
            .read(documentProvider(_docId!).notifier)
            .replaceImage(widget.replacePageId!, result.bytes, result.width, result.height, result.corners);
        if (mounted) Navigator.of(context).pop(true);
      } catch (e) {
        _showError(l.couldNotSavePage);
        if (mounted) setState(() => _saving--);
        await controller.resume();
      }
      return;
    }
    if (_docId == null) {
      final doc = await ref.read(libraryActionsProvider).createDocument();
      _docId = _createdId = doc.id;
      _keepDocumentAlive(doc.id);
    }
    final pageNumber = (ref.read(documentProvider(_docId!)).value?.pages.length ?? 0) + _saving + 1;
    setState(() => _saving++);
    // Process the page in the background and keep scanning.
    unawaited(
      ref
          .read(documentProvider(_docId!).notifier)
          .addImage(result.bytes, result.width, result.height, result.corners)
          .catchError((Object e) => _showError(l.couldNotSavePage))
          .whenComplete(() {
            if (mounted) setState(() => _saving--);
          }),
    );
    if (mounted) ref.read(scanGuidanceProvider).captured(context, pageNumber);
    await controller.resume();
  }

  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _uploadPhoto() async {
    final files = await ref.read(importServiceProvider).pickImages();
    if (files.isEmpty || !mounted) return;
    await ref.read(captureControllerProvider.notifier).useUploadedPhoto(files.first.bytes);
  }

  Future<void> _done() async {
    final id = _docId;
    if (id == null) return;
    if (widget.documentId != null) {
      Navigator.of(context).pop(); // came from the editor
    } else {
      await Navigator.of(context)
          .pushReplacement(MaterialPageRoute<void>(builder: (_) => DocumentEditorPage(documentId: id)));
    }
  }

  /// Thumbnail of the last page with a "Review N pages" label.
  Widget _pagesButton(ScanDocument? doc) {
    final l = context.l10n;
    final pages = doc?.pages ?? const <ScanPage>[];
    final count = pages.length + _saving;
    if (count == 0 || _replacing) return const SizedBox(width: _sideWidth);
    final label = _saving > 0 ? l.savingPages : l.reviewPages(count);
    return SizedBox(
      width: _sideWidth,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('review-pages'),
          onTap: _saving > 0 ? null : _done,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 52,
                  height: 64,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            color: Colors.white10,
                          ),
                          child: pages.isEmpty ? null : StoredPageImage(page: pages.last, fit: BoxFit.cover),
                        ),
                      ),
                      if (_saving > 0)
                        const Positioned.fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _sideWidth = 112.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.listen(captureControllerProvider.select((s) => s.pendingCapture), (prev, next) {
      if (next != null && prev == null) _openEditor(next);
    });
    ref.listen(captureControllerProvider.select((s) => s.message), (_, msg) {
      if (msg == null) return;
      final text = switch (msg) {
        CaptureMessage.captureFailed => l.msgCaptureFailed,
        CaptureMessage.badPhotoFile => l.msgBadPhotoFile,
        CaptureMessage.noFlashlight => l.msgNoFlashlight,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      ref.read(captureControllerProvider.notifier).clearMessage();
    });
    ref.listen(
      captureControllerProvider.select(ScanHint.of),
      (_, hint) => ref.read(scanGuidanceProvider).hint(context, hint),
    );

    ref.watch(scanGuidanceProvider); // keep guidance (and its timers) alive while scanning
    final state = ref.watch(captureControllerProvider);
    final controller = ref.read(captureControllerProvider.notifier);
    final demo = ref.watch(cameraModeProvider) == CameraMode.demo;
    final simple = ref.watch(appSettingsProvider.select((s) => s.simpleMode));
    final doc = _docId == null ? null : ref.watch(documentProvider(_docId!)).value;
    final cam = controller.camera;
    final busy = state.status == CaptureStatus.capturing || state.status == CaptureStatus.reviewing;

    // Every control is an icon with a text label.
    final controls = <Widget>[
      if (state.status == CaptureStatus.running && state.supportsTorch)
        _ControlButton(
          key: const ValueKey('torch'),
          icon: state.torchOn ? Icons.flash_on : Icons.flash_off,
          label: state.torchOn ? l.flashOn : l.flashOff,
          selected: state.torchOn,
          onPressed: () => controller.setTorch(!state.torchOn),
        ),
      if (state.status == CaptureStatus.running && state.cameraCount > 1 && !demo)
        _ControlButton(
          key: const ValueKey('switch-camera'),
          icon: Icons.cameraswitch_outlined,
          label: l.switchCamera,
          onPressed: controller.switchCamera,
        ),
      if (state.status == CaptureStatus.running)
        _ControlButton(
          key: const ValueKey('auto-capture'),
          icon: state.autoCapture ? Icons.motion_photos_auto_outlined : Icons.touch_app_outlined,
          label: state.autoCapture ? l.autoCaptureOn : l.autoCaptureOff,
          selected: state.autoCapture,
          onPressed: () => controller.setAutoCapture(!state.autoCapture),
        ),
      if (cam is DemoScannerCamera && state.status == CaptureStatus.running)
        _ControlButton(icon: Icons.skip_next, label: l.nextSample, onPressed: cam.nextSample),
      if (state.status != CaptureStatus.failed)
        _ControlButton(
          key: const ValueKey('upload-photo'),
          icon: Icons.upload_file,
          label: l.uploadPhoto,
          onPressed: busy ? null : _uploadPhoto,
        ),
      if (!simple || demo)
        _ControlButton(
          icon: demo ? Icons.videocam_outlined : Icons.slideshow_outlined,
          label: demo ? l.useDeviceCamera : l.useDemoCamera,
          onPressed: () => ref.read(cameraModeProvider.notifier).set(demo ? CameraMode.device : CameraMode.demo),
        ),
      if (!simple)
        _ControlButton(
          icon: Icons.query_stats,
          label: l.diagnostics,
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DetectorDiagnosticsPage())),
        ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        titleSpacing: 4,
        title: Row(
          children: [
            TextButton.icon(
              key: const ValueKey('cancel-scan'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
              label: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _replacing ? l.retakeTitle : (demo ? l.scanDemoTitle : l.scanTitle),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: switch (state.status) {
              CaptureStatus.failed => _FailureView(
                failure: state.failure!,
                onRetry: controller.restart,
                onDemo: () => ref.read(cameraModeProvider.notifier).set(CameraMode.demo),
                onUpload: _uploadPhoto,
              ),
              CaptureStatus.starting || CaptureStatus.suspended => const _Starting(),
              _ => _Viewfinder(state: state, camera: cam),
            },
          ),
          if (demo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.demoCameraNote, style: const TextStyle(color: Colors.white)),
            ),
          if (controls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: controls),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              // Wraps onto two lines on narrow screens / large text instead of overflowing.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: [
                  _pagesButton(doc),
                  if (state.status != CaptureStatus.failed)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShutterButton(
                          label: l.capture,
                          progress: state.autoCapture ? state.steadyProgress : 0,
                          busy: state.status == CaptureStatus.capturing,
                          onPressed: state.status == CaptureStatus.running ? controller.capture : null,
                        ),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: Text(l.capture, style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: _sideWidth),
                    child: (doc?.pages.isNotEmpty ?? false) && _saving == 0 && !_replacing
                        ? FilledButton.icon(
                            key: const ValueKey('capture-done'),
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                            onPressed: _done,
                            icon: const Icon(Icons.check),
                            label: Text(l.done, maxLines: 1),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: selected ? Colors.black : Colors.white,
      backgroundColor: selected ? Colors.white : Colors.white12,
      disabledForegroundColor: Colors.white60,
      side: const BorderSide(color: Colors.white70),
    ),
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}

/// What the scanner tells the user right now (shown, and optionally spoken).
enum ScanHint {
  capturing,
  tooDarkFlash,
  tooDark,
  pointCamera,
  moveCloser,
  holdStill,
  found,
  nextPage,
  tapShutter,
  none;

  static ScanHint of(CaptureState s) {
    if (s.status == CaptureStatus.capturing) return capturing;
    if (s.status != CaptureStatus.running) return none;
    if (s.lowLight) return s.supportsTorch ? tooDarkFlash : tooDark;
    if (!s.documentFound) return s.tooSmall ? moveCloser : pointCamera;
    if (s.autoCapture && s.awaitingNextPage) return nextPage;
    if (s.autoCapture) return s.steadyProgress > 0.2 ? holdStill : found;
    return tapShutter;
  }

  String text(AppLocalizations l) => switch (this) {
    capturing => l.capturing,
    tooDarkFlash => l.hintTooDarkFlash,
    tooDark => l.hintTooDark,
    pointCamera => l.hintPointCamera,
    moveCloser => l.hintMoveCloser,
    holdStill => l.hintHoldStill,
    found => l.hintFound,
    nextPage => l.hintNextPage,
    tapShutter => l.hintTapShutter,
    none => '',
  };
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.state, required this.camera});
  final CaptureState state;
  final ScannerCamera? camera;

  @override
  Widget build(BuildContext context) {
    final cam = camera;
    final hint = ScanHint.of(state);
    const accent = Color(0xFF29B6F6); // bright blue that reads on any camera image
    return Center(
      child: AspectRatio(
        aspectRatio: state.previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cam != null) ExcludeSemantics(child: cam.buildPreview()),
            LiveQuadOverlay(corners: state.corners, progress: state.steadyProgress, color: accent),
            if (hint != ScanHint.none)
              Positioned(
                left: 0,
                right: 0,
                top: 12,
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    child: _HintPill(text: hint.text(context.l10n), warning: state.lowLight),
                  ),
                ),
              ),
            // Shutter flash (skipped when the system asks for reduced motion).
            if (!MediaQuery.disableAnimationsOf(context))
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: state.status == CaptureStatus.capturing ? 0.6 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text, required this.warning});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: warning ? const Color(0xFF8A4B00) : Colors.black87, // white text stays >= 4.5:1 over any camera image
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    ),
  );
}

class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(context.l10n.startingCamera, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.failure, required this.onRetry, required this.onDemo, required this.onUpload});
  final CameraFailure failure;
  final VoidCallback onRetry, onDemo, onUpload;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (icon, title, body) = switch (failure.kind) {
      CameraFailureKind.permissionDenied => (Icons.no_photography, l.camOffTitle, kIsWeb ? l.camOffWeb : l.camOffApp),
      CameraFailureKind.noCamera => (Icons.videocam_off, l.noCameraTitle, l.noCameraBody),
      CameraFailureKind.inUse => (Icons.videocam_off, l.cameraBusyTitle, l.cameraBusyBody),
      CameraFailureKind.unsupported => (Icons.lock, l.cameraHttpsTitle, kIsWeb ? l.cameraHttpsBody : failure.message),
      CameraFailureKind.other => (Icons.error_outline, l.cameraErrorTitle, failure.message),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 56),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('failure-upload'),
                  onPressed: onUpload,
                  icon: const Icon(Icons.upload_file),
                  label: Text(l.uploadPhoto),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(l.tryAgain),
                ),
                if (failure.kind == CameraFailureKind.permissionDenied && !kIsWeb)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l.openSettings),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  onPressed: onDemo,
                  icon: const Icon(Icons.slideshow_outlined),
                  label: Text(l.useDemoCamera),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
