// Accessibility checks on every main screen, using Flutter's guideline
// matchers: tap targets >= 48x48 (Android) / 44x44 (iOS), every tappable
// thing has a label, text contrast >= 4.5:1 (3:1 for large text). Also: 200%
// text without overflow, light/dark/high contrast, keyboard use.
import 'dart:io';
import 'dart:math' as math;

import 'package:docscanner/core/app_settings.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/core/theme.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/account/account_page.dart';
import 'package:docscanner/features/capture/capture_page.dart';
import 'package:docscanner/features/editor/document_editor_page.dart';
import 'package:docscanner/features/home/home_page.dart';
import 'package:docscanner/features/library/documents_page.dart';
import 'package:docscanner/features/markup/markup_editor_page.dart';
import 'package:docscanner/features/onboarding/onboarding_page.dart';
import 'package:docscanner/features/settings/settings_page.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/services/camera/scanner_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';
import '../support/test_app.dart';

final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();

Future<MemoryStore> seed() async {
  final store = MemoryStore();
  final repo = DocumentRepository(store);
  final pages = [
    for (var i = 0; i < 2; i++)
      ScanPage(
        id: 'p$i',
        sourceWidth: 583,
        sourceHeight: 800,
        corners: fullBounds(583, 800),
        renderWidth: 583,
        renderHeight: 800,
        revision: 1,
      ),
  ];
  for (final p in pages) {
    for (final k in PageImage.values) {
      await repo.putPageImage(p.id, k, png);
    }
  }
  await repo.save(ScanDocument(id: 'd', title: 'Lease agreement', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: pages));
  return store;
}

enum Look { light, dark, highContrast }

Future<void> pumpScreen(WidgetTester tester, Widget screen, MemoryStore store,
    {double textScale = 1, Look look = Look.light, Size size = const Size(420, 900), CameraFailure? cameraFailure}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final engine = FakeEngine(frameDetector: (_) => noPage);
  final dark = look == Look.dark;
  await tester.pumpWidget(testApp(
    MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: Theme(
        data: buildTheme(brightness: dark ? Brightness.dark : Brightness.light, highContrast: look == Look.highContrast),
        child: screen,
      ),
    ),
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      scanEngineProvider.overrideWithValue(engine),
      appSettingsProvider.overrideWith(() => AppSettingsNotifier(const AppSettings(serverUrl: 'http://localhost:8000'))),
      pageRendererProvider.overrideWith(
        (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (583, 800)),
      ),
      cameraFactoryProvider.overrideWithValue(() => FakeCamera(failure: cameraFailure)),
    ],
  ));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}

/// Stop scanner loops / timers before the test ends.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> expectGuidelines(WidgetTester tester, {bool contrast = true}) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contrast) await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

final screens = <String, Widget>{
  'home': const HomePage(),
  'documents': const DocumentsPage(),
  'editor': const DocumentEditorPage(documentId: 'd'),
  'markup': const MarkupEditorPage(documentId: 'd', pageId: 'p0'),
  'settings': const SettingsPage(),
  'onboarding': const OnboardingPage(),
  'account (optional sign-in)': const AccountPage(),
};

void main() {
  for (final MapEntry(key: name, value: screen) in screens.entries) {
    for (final look in Look.values) {
      testWidgets('$name (${look.name}): tap targets, labels, contrast', (tester) async {
        final store = (await tester.runAsync(seed))!;
        await pumpScreen(tester, screen, store, look: look);
        // Page images are photos, not text: contrast is only checked on the UI chrome screens.
        await expectGuidelines(tester, contrast: name != 'editor' && name != 'markup');
      });
    }

    testWidgets('$name at 200% text: no overflow', (tester) async {
      final store = (await tester.runAsync(seed))!;
      await pumpScreen(tester, screen, store, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scanner running: guidelines and 200% text', (tester) async {
    final store = (await tester.runAsync(seed))!;
    await pumpScreen(tester, const CapturePage(), store);
    await expectGuidelines(tester, contrast: false); // the camera image is behind the text pills
    await unmount(tester);
    await pumpScreen(tester, const CapturePage(), store, textScale: 2);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('scanner error screen: guidelines incl. contrast, 200% text', (tester) async {
    final store = (await tester.runAsync(seed))!;
    const failure = CameraFailure(CameraFailureKind.permissionDenied);
    await pumpScreen(tester, const CapturePage(), store, cameraFailure: failure);
    await expectGuidelines(tester);
    await unmount(tester);
    await pumpScreen(tester, const CapturePage(), store, cameraFailure: failure, textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard only: Tab order on Home, Enter opens the scanner', (tester) async {
    final store = (await tester.runAsync(seed))!;
    await pumpScreen(tester, const HomePage(), store);
    String focusedText() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      return ctx == null
          ? ''
          : find.descendant(of: find.byWidget(ctx.widget), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join(' ');
    }

    final order = <String>[];
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(focusedText());
    }
    expect(order, ['Settings', 'Scan Document', 'Import Photos', 'Import PDF', 'View Documents']);
    // Back to "Scan Document" and press Enter.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    }
    await tester.pump();
    expect(focusedText(), 'Scan Document');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CapturePage), findsOneWidget);
    await unmount(tester);
  });

  test('theme colours meet 4.5:1 for text in every look', () {
    double lum(Color c) {
      // WCAG relative luminance.
      double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    double ratio(Color a, Color b) {
      final x = lum(a), y = lum(b);
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    for (final dark in [false, true]) {
      for (final hc in [false, true]) {
        final s = buildTheme(brightness: dark ? Brightness.dark : Brightness.light, highContrast: hc).colorScheme;
        final pairs = {
          'onSurface/surface': (s.onSurface, s.surface),
          'onSurfaceVariant/surface': (s.onSurfaceVariant, s.surface),
          'onPrimary/primary': (s.onPrimary, s.primary),
          'primary/surface': (s.primary, s.surface),
          'error/surface': (s.error, s.surface),
          'onError/error': (s.onError, s.error),
          'onSecondaryContainer/secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
          'onSurface/surfaceContainerLow': (s.onSurface, s.surfaceContainerLow),
        };
        for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
          expect(ratio(fg, bg), greaterThanOrEqualTo(4.5), reason: '$name dark=$dark highContrast=$hc');
        }
      }
    }
    // Scanner hint pills: white text on the pill colours.
    expect(ratio(Colors.white, const Color(0xFF8A4B00)), greaterThanOrEqualTo(4.5));
  });
}
