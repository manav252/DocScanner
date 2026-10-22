// Live scanner: camera preview + detected outline, auto/manual capture.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/geometry.dart';
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

  @override
  void initState() {
    super.initState();
    _repo; // capture before dispose, where ref may no longer be used
    if (_docId != null) _keepDocumentAlive(_docId!);
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
    final corners = await Navigator.of(context).push<List<Pt>>(MaterialPageRoute(
      builder: (_) => CornerAdjustPage(
        bytes: capture.bytes,
        width: capture.width,
        height: capture.height,
        corners: capture.corners,
        detected: capture.detected,
        confirmLabel: _replacing ? 'Replace page' : 'Keep scan',
      ),
    ));
    if (!mounted) return;
    final controller = ref.read(captureControllerProvider.notifier);
    if (corners == null) {
      await controller.resume();
      return;
    }
    if (_replacing) {
      setState(() => _saving++);
      try {
        await ref
            .read(documentProvider(_docId!).notifier)
            .replaceImage(widget.replacePageId!, capture.bytes, capture.width, capture.height, corners);
        if (mounted) Navigator.of(context).pop(true);
      } catch (e) {
        _showError('Could not save the page: $e');
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
    setState(() => _saving++);
    // Process the page in the background and keep scanning.
    unawaited(ref
        .read(documentProvider(_docId!).notifier)
        .addImage(capture.bytes, capture.width, capture.height, corners)
        .catchError((Object e) => _showError('Could not save the page: $e'))
        .whenComplete(() {
      if (mounted) setState(() => _saving--);
    }));
    await controller.resume();
  }

  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _done() async {
    final id = _docId;
    if (id == null) return;
    if (widget.documentId != null) {
      Navigator.of(context).pop(); // came from the editor
    } else {
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => DocumentEditorPage(documentId: id)));
    }
  }

  Widget _pagesButton(ScanDocument? doc) {
    final pages = doc?.pages ?? const <ScanPage>[];
    final count = pages.length + _saving;
    if (count == 0 || _replacing) return const SizedBox(width: 88);
    return Semantics(
      button: true,
      label: '$count pages, review',
      child: GestureDetector(
        onTap: _saving > 0 ? null : _done,
        child: SizedBox(
          width: 88,
          height: 72,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), color: Colors.white10),
                child: pages.isEmpty ? null : StoredPageImage(page: pages.last, fit: BoxFit.cover),
              ),
            ),
            if (_saving > 0)
              const Positioned.fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            Positioned(
              right: -8,
              top: -8,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(captureControllerProvider.select((s) => s.pendingCapture), (prev, next) {
      if (next != null && prev == null) _openEditor(next);
    });
    ref.listen(captureControllerProvider.select((s) => s.message), (_, msg) {
      if (msg == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      ref.read(captureControllerProvider.notifier).clearMessage();
    });

    final state = ref.watch(captureControllerProvider);
    final controller = ref.read(captureControllerProvider.notifier);
    final demo = ref.watch(cameraModeProvider) == CameraMode.demo;
    final doc = _docId == null ? null : ref.watch(documentProvider(_docId!)).value;
    final cam = controller.camera;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_replacing ? 'Retake page' : (demo ? 'Scan (demo)' : 'Scan')),
        actions: [
          if (cam is DemoScannerCamera)
            IconButton(tooltip: 'Next sample page', icon: const Icon(Icons.skip_next), onPressed: cam.nextSample),
          if (state.supportsTorch)
            IconButton(
              tooltip: state.torchOn ? 'Flashlight off' : 'Flashlight on',
              icon: Icon(state.torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: () => controller.setTorch(!state.torchOn),
            ),
          _AutoChip(on: state.autoCapture, onChanged: controller.setAutoCapture),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'demo':
                  ref.read(cameraModeProvider.notifier).set(demo ? CameraMode.device : CameraMode.demo);
                case 'diag':
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DetectorDiagnosticsPage()));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'demo', child: Text(demo ? 'Use device camera' : 'Use demo camera')),
              const PopupMenuItem(value: 'diag', child: Text('Detector diagnostics')),
            ],
          ),
        ],
      ),
      body: switch (state.status) {
        CaptureStatus.failed => _FailureView(
            failure: state.failure!,
            onRetry: controller.restart,
            onDemo: () => ref.read(cameraModeProvider.notifier).set(CameraMode.demo),
          ),
        CaptureStatus.starting || CaptureStatus.suspended => const _Starting(),
        _ => _Viewfinder(
            state: state,
            camera: cam,
            onCapture: controller.capture,
            leading: _pagesButton(doc),
            trailing: (doc?.pages.isNotEmpty ?? false) && _saving == 0 && !_replacing
                ? FilledButton(
                    key: const ValueKey('capture-done'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: _done,
                    child: const Text('Done', maxLines: 1),
                  )
                : null,
          ),
      },
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.state,
    required this.camera,
    required this.onCapture,
    required this.leading,
    this.trailing,
  });
  final CaptureState state;
  final ScannerCamera? camera;
  final Future<void> Function() onCapture;
  final Widget leading;
  final Widget? trailing;

  String get _hint {
    if (state.status == CaptureStatus.capturing) return 'Capturing…';
    if (state.lowLight) return state.supportsTorch ? 'Too dark: turn on the flashlight' : 'Too dark: add more light';
    if (!state.documentFound) return 'Point the camera at a document';
    if (state.autoCapture) return state.steadyProgress > 0.2 ? 'Hold steady…' : 'Document found';
    return 'Document found: tap the shutter';
  }

  @override
  Widget build(BuildContext context) {
    final cam = camera;
    const accent = Color(0xFF29B6F6); // bright blue that reads on any camera image
    return Column(children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: state.previewAspectRatio,
            child: Stack(fit: StackFit.expand, children: [
              if (cam != null) cam.buildPreview(),
              LiveQuadOverlay(corners: state.corners, progress: state.steadyProgress, color: accent),
              Positioned(
                left: 0,
                right: 0,
                top: 12,
                child: Center(child: _HintPill(text: _hint, warning: state.lowLight)),
              ),
              // Shutter flash.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: state.status == CaptureStatus.capturing ? 0.6 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          leading,
          ShutterButton(
            progress: state.autoCapture ? state.steadyProgress : 0,
            busy: state.status == CaptureStatus.capturing,
            onPressed: state.status == CaptureStatus.running ? onCapture : null,
          ),
          SizedBox(
            width: 88,
            child: trailing ??
                Text(
                  state.fps > 0 ? '${state.fps.toStringAsFixed(0)} fps' : '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
          ),
        ]),
      ),
    ]);
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text, required this.warning});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: warning ? const Color(0xE6B26A00) : Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(text, style: const TextStyle(color: Colors.white)),
        ),
      );
}

class _AutoChip extends StatelessWidget {
  const _AutoChip({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilterChip(
          label: Text(on ? 'Auto' : 'Manual'),
          avatar: Icon(on ? Icons.auto_awesome : Icons.touch_app, size: 18),
          selected: on,
          showCheckmark: false,
          onSelected: onChanged,
        ),
      );
}

class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Starting camera…', style: TextStyle(color: Colors.white70)),
        ]),
      );
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.failure, required this.onRetry, required this.onDemo});
  final CameraFailure failure;
  final VoidCallback onRetry, onDemo;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (failure.kind) {
      CameraFailureKind.permissionDenied => (
          Icons.no_photography,
          'Camera access is off',
          kIsWeb
              ? 'Allow camera access for this site (camera icon in the address bar), then try again.'
              : 'Allow camera access for DocScanner in Settings, then try again.',
        ),
      CameraFailureKind.noCamera => (Icons.videocam_off, 'No camera found', 'Connect a camera, or try the demo camera.'),
      CameraFailureKind.inUse => (
          Icons.videocam_off,
          'Camera is busy',
          'Another app or browser tab is using the camera. Close it and try again.',
        ),
      CameraFailureKind.unsupported => (
          Icons.lock,
          'Camera not available here',
          kIsWeb ? 'Browsers only allow the camera on https:// pages or localhost.' : failure.message,
        ),
      CameraFailureKind.other => (Icons.error_outline, 'Could not start the camera', failure.message),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            if (failure.kind == CameraFailureKind.permissionDenied && !kIsWeb)
              OutlinedButton(onPressed: openAppSettings, child: const Text('Open Settings')),
            OutlinedButton(onPressed: onDemo, child: const Text('Use demo camera')),
          ]),
        ]),
      ),
    );
  }
}
