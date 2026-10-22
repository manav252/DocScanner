// App-wide service providers. Tests override these with fakes.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';

import '../data/document_repository.dart';
import '../data/page_renderer.dart';
import '../data/storage/key_value_store.dart';
import '../imaging/scan_engine.dart';
import '../imaging/server_scan_engine.dart';
import '../services/export/share_service.dart';
import '../services/import/import_service.dart';
import '../services/ocr/text_recognizer.dart';
import '../services/camera/demo_scanner_camera.dart';
import '../services/camera/scanner_camera.dart';

/// The on-device OpenCV engine (isolate on mobile, Web Worker on web). Lives for the whole app.
final localScanEngineProvider = Provider<ScanEngine>((ref) {
  final engine = ScanEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// The engine features use: on-device, or the server for still images when
/// "Process on server" is on and the user is signed in.
final scanEngineProvider = Provider<ScanEngine>((ref) {
  final local = ref.watch(localScanEngineProvider);
  final useServer = ref.watch(appSettingsProvider.select((s) => s.processOnServer)) && ref.watch(sessionProvider) != null;
  return useServer ? ServerScanEngine(local, ref.watch(apiClientProvider)) : local;
});

enum CameraMode { device, demo }

class CameraModeNotifier extends Notifier<CameraMode> {
  CameraModeNotifier([this._initial = CameraMode.device]);
  final CameraMode _initial;

  @override
  CameraMode build() => _initial;

  void set(CameraMode mode) => state = mode;
}

final cameraModeProvider = NotifierProvider<CameraModeNotifier, CameraMode>(CameraModeNotifier.new);

/// Which of the device's cameras the scanner uses (see [ScannerCamera.cameraCount]).
class CameraIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void next(int count) => state = count <= 1 ? 0 : (state + 1) % count;
}

final cameraIndexProvider = NotifierProvider<CameraIndexNotifier, int>(CameraIndexNotifier.new);

/// Creates a fresh camera each time the scanner opens.
final cameraFactoryProvider = Provider<ScannerCamera Function()>((ref) {
  final index = ref.watch(cameraIndexProvider);
  return switch (ref.watch(cameraModeProvider)) {
    CameraMode.device => () => ScannerCamera.device(index: index),
    CameraMode.demo => DemoScannerCamera.new,
  };
});

/// Opened in main() (IndexedDB on web, files on mobile) and injected via override.
final keyValueStoreProvider = Provider<KeyValueStore>((_) => throw UnimplementedError('override in main()'));

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  final repo = DocumentRepository(ref.watch(keyValueStoreProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final pageRendererProvider = Provider<PageRenderer>(
  (ref) => PageRenderer(ref.watch(scanEngineProvider), ref.watch(documentRepositoryProvider)),
);

final importServiceProvider = Provider<ImportService>((_) => const ImportService());
final shareServiceProvider = Provider<ShareService>((_) => const ShareService());

final textRecognizerProvider = Provider<TextRecognizer>((ref) {
  final r = TextRecognizer();
  ref.onDispose(r.dispose);
  return r;
});
