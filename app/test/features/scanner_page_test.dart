// Scanner screen: labelled controls, camera switch, "Upload a photo" when there
// is no camera, clear error screens, and spoken/haptic guidance.

import 'dart:io';

import 'package:docscanner/core/app_settings.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/capture/capture_page.dart';
import 'package:docscanner/features/capture/scan_guidance.dart';
import 'package:docscanner/features/corners/corner_adjust_page.dart';
import 'package:docscanner/services/camera/scanner_camera.dart';
import 'package:docscanner/services/import/import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';
import '../support/test_app.dart';

class OnePhotoImporter extends ImportService {
  int picks = 0;
  @override
  Future<List<ImportedFile>> pickImages() async {
    picks++;
    return [ImportedFile('page.png', File('${fixturesDir.path}/filters/input.png').readAsBytesSync())];
  }
}

class FakeSpeaker implements Speaker {
  final said = <(String, String)>[];
  @override
  Future<void> speak(String text, {required String languageTag}) async => said.add((text, languageTag));
  @override
  Future<void> stop() async {}
}

/// Close the scanner and let its frame loop finish.
Future<void> stop(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late List<int> openedIndexes;

  Future<ProviderContainer> open(
    WidgetTester tester, {
    CameraFailure? failure,
    int cameras = 1,
    ImportService? importer,
    AppSettings settings = const AppSettings(serverUrl: ''),
    Speaker? speaker,
  }) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    openedIndexes = [];
    await tester.pumpWidget(testApp(
      const CapturePage(),
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryStore()),
        scanEngineProvider.overrideWithValue(FakeEngine(frameDetector: (_) => noPage, stillDetection: null)),
        appSettingsProvider.overrideWith(() => AppSettingsNotifier(settings)),
        cameraFactoryProvider.overrideWith((ref) {
          final index = ref.watch(cameraIndexProvider);
          return () {
            openedIndexes.add(index);
            return FakeCamera(failure: failure)..cameraCount = cameras;
          };
        }),
        if (importer != null) importServiceProvider.overrideWithValue(importer),
        if (speaker != null) speakerProvider.overrideWithValue(speaker),
      ],
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    return ProviderScope.containerOf(tester.element(find.byType(CapturePage)));
  }

  Finder button(String label) =>
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  testWidgets('running scanner: every control has a text label; no icon-only buttons', (tester) async {
    await open(tester);
    for (final label in ['Cancel', 'Flashlight off', 'Auto capture: on', 'Upload a photo', 'Capture']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Switch camera'), findsNothing, reason: 'only one camera');
    expect(find.text('Point the camera at a document'), findsOneWidget);

    await tester.tap(button('Auto capture: on'));
    await tester.pump();
    expect(find.text('Auto capture: off'), findsOneWidget);
    await tester.tap(button('Flashlight off'));
    await tester.pump();
    expect(find.text('Flashlight on'), findsOneWidget);
    await stop(tester);
  });

  testWidgets('Switch camera opens the next camera', (tester) async {
    await open(tester, cameras: 2);
    expect(openedIndexes, [0]);
    await tester.tap(button('Switch camera'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(openedIndexes, [0, 1]);
    await stop(tester);
  });

  testWidgets('no camera: clear message, Upload a photo opens the corner review, Retake returns', (tester) async {
    final importer = OnePhotoImporter();
    await open(tester, failure: const CameraFailure(CameraFailureKind.noCamera), importer: importer);
    expect(find.text('No camera found'), findsOneWidget);
    expect(find.textContaining('Upload a photo of the page'), findsOneWidget);
    for (final label in ['Upload a photo', 'Try again', 'Use demo camera']) {
      expect(button(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.byKey(const ValueKey('failure-upload')));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(importer.picks, 1);
    expect(find.byType(CornerAdjustPage), findsOneWidget);
    expect(find.text(CornerAdjustPage.noEdgesMessage), findsOneWidget);
    expect(find.text('Keep scan'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cancel-corners')));
    await tester.pumpAndSettle();
    expect(find.byType(CornerAdjustPage), findsNothing);
    expect(find.text('No camera found'), findsOneWidget, reason: 'back to the fallback screen');
  });

  testWidgets('camera permission denied: says how to fix it', (tester) async {
    await open(tester, failure: const CameraFailure(CameraFailureKind.permissionDenied));
    expect(find.text('Camera access is off'), findsOneWidget);
    expect(find.textContaining('You can also upload a photo instead'), findsOneWidget);
  });

  group('guidance', () {
    Future<(ScanGuidance, BuildContext, FakeSpeaker)> harness(WidgetTester tester, {required bool spoken, Locale locale = const Locale('en')}) async {
      final speaker = FakeSpeaker();
      late BuildContext ctx;
      late ScanGuidance g;
      await tester.pumpWidget(testApp(
        Consumer(builder: (context, ref, _) {
          ctx = context;
          g = ref.watch(scanGuidanceProvider);
          return const SizedBox();
        }),
        locale: locale,
        overrides: [
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          appSettingsProvider.overrideWith(() => AppSettingsNotifier(AppSettings(serverUrl: '', spokenGuidance: spoken))),
          speakerProvider.overrideWithValue(speaker),
        ],
      ));
      return (g, ctx, speaker);
    }

    testWidgets('speaks settled hints once, skips flicker, announces captures', (tester) async {
      final (g, ctx, speaker) = await harness(tester, spoken: true);
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
        return null;
      });

      g.hint(ctx, ScanHint.moveCloser);
      await tester.pump(const Duration(milliseconds: 300));
      g.hint(ctx, ScanHint.holdStill); // replaces the pending hint before it is said
      await tester.pump(const Duration(milliseconds: 800));
      expect(speaker.said, [('Hold still', 'en-US')]);
      g.hint(ctx, ScanHint.found);
      g.hint(ctx, ScanHint.holdStill);
      await tester.pump(const Duration(seconds: 1));
      expect(speaker.said, hasLength(1), reason: 'not repeated within 6 s');

      g.captured(ctx, 2);
      expect(speaker.said.last, ('Captured, page 2', 'en-US'));
      expect(haptics, containsAll(['HapticFeedbackType.selectionClick', 'HapticFeedbackType.mediumImpact']));
    });

    testWidgets('setting off: nothing is spoken', (tester) async {
      final (g, ctx, speaker) = await harness(tester, spoken: false);
      g.hint(ctx, ScanHint.moveCloser);
      await tester.pump(const Duration(seconds: 1));
      g.captured(ctx, 1);
      expect(speaker.said, isEmpty);
    });

    testWidgets('Hindi: spoken in Hindi', (tester) async {
      final (g, ctx, speaker) = await harness(tester, spoken: true, locale: const Locale('hi'));
      g.hint(ctx, ScanHint.holdStill);
      await tester.pump(const Duration(seconds: 1));
      expect(speaker.said.single, ('स्थिर रखें', 'hi-IN'));
    });
  });
}
