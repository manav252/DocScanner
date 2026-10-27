// App-wide service providers. Tests override these with fakes.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';

import '../data/document_repository.dart';
import '../data/backup.dart';
import '../data/page_renderer.dart';
import '../data/thumbnails.dart';
import '../data/storage/key_value_store.dart';
import '../imaging/scan_engine.dart';
import '../imaging/server_scan_engine.dart';
import '../services/export/share_service.dart';
import '../services/import/import_service.dart';
import '../services/ocr/text_recognizer.dart';
import '../services/camera/demo_scanner_camera.dart';
import '../services/camera/scanner_camera.dart';
import 'crash_note.dart';

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
  final useServer =
      ref.watch(appSettingsProvider.select((s) => s.processOnServer)) && ref.watch(sessionProvider) != null;
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

/// Cached page previews for lists (see ThumbnailService).
final thumbnailServiceProvider = Provider<ThumbnailService>(
  (ref) => ThumbnailService(ref.watch(documentRepositoryProvider), ref.watch(scanEngineProvider)),
);

/// Export/import of all documents as a ZIP (backup without an account).
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(documentRepositoryProvider), ref.watch(keyValueStoreProvider)),
);

/// Space used on this device and how many documents there are.
final storageUsageProvider = FutureProvider.autoDispose<({int? bytes, int documents, int pages})>((ref) async {
  final docs = await ref.watch(documentRepositoryProvider).list();
  return (
    bytes: await ref.watch(keyValueStoreProvider).usageBytes(),
    documents: docs.length,
    pages: docs.fold<int>(0, (n, d) => n + d.pages.length),
  );
});

/// Upkeep a few seconds after start: missing thumbnails, leftovers of interrupted deletes.
final maintenanceProvider = FutureProvider<(int, int)>((ref) async {
  await Future<void>.delayed(const Duration(seconds: 3));
  try {
    return await ref.read(thumbnailServiceProvider).repair();
  } catch (_) {
    return (0, 0); // best effort; previews fall back to a placeholder anyway
  }
});

final pageRendererProvider = Provider<PageRenderer>(
  (ref) => PageRenderer(ref.watch(scanEngineProvider), ref.watch(documentRepositoryProvider)),
);

final importServiceProvider = Provider<ImportService>((_) => const ImportService());
final shareServiceProvider = Provider<ShareService>((_) => const ShareService());

/// Left by a previous session that closed during a step (web; see crash_note.dart).
final lastCrashProvider = Provider<CrashNote?>((_) => null);

/// The scanner screen (camera) is open. Text recognition waits meanwhile, so
/// the camera, detection and OCR never all use memory at once (iPhone Safari
/// kills a tab that uses too much).
class CameraActive extends Notifier<bool> {
  @override
  bool build() => false;
  set active(bool v) {
    if (ref.mounted) state = v; // the scanner may close after the app's providers (tests)
  }
}

final cameraActiveProvider = NotifierProvider<CameraActive, bool>(CameraActive.new);

final textRecognizerProvider = Provider<TextRecognizer>((ref) {
  final r = TextRecognizer();
  ref.onDispose(r.dispose);
  return r;
});
