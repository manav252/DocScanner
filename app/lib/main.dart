import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_settings.dart';
import 'core/providers.dart';
import 'data/storage/key_value_store.dart';
import 'data/sync/sync_controller.dart';
import 'features/library/library_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await KeyValueStore.open();
  final (settings, session) = await loadSettingsAndSession(store);
  // `?demo=1` on the web (or --dart-define=DEMO_CAMERA=true) starts with the demo camera.
  final demo = const bool.fromEnvironment('DEMO_CAMERA') || (kIsWeb && Uri.base.queryParameters['demo'] == '1');
  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        appSettingsProvider.overrideWith(() => AppSettingsNotifier(settings)),
        sessionProvider.overrideWith(() => SessionNotifier(session)),
        if (demo) cameraModeProvider.overrideWith(() => CameraModeNotifier(CameraMode.demo)),
      ],
      child: const DocScannerApp(),
    ),
  );
}

class DocScannerApp extends ConsumerWidget {
  const DocScannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start background sync for the whole app lifetime.
    ref.watch(syncControllerProvider);
    return MaterialApp(
      title: 'DocScanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0), brightness: Brightness.dark, useMaterial3: true),
      home: const LibraryPage(),
    );
  }
}
