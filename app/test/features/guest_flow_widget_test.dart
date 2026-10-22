// Everything works without an account: home, recent scans, documents, search,
// settings (sign-in optional), first-run guide, Hindi.
import 'dart:io';

import 'package:docscanner/core/app_settings.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/editor/document_editor_page.dart';
import 'package:docscanner/features/home/home_page.dart';
import 'package:docscanner/features/library/documents_page.dart';
import 'package:docscanner/features/onboarding/onboarding_page.dart';
import 'package:docscanner/features/settings/settings_page.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';
import '../support/test_app.dart';

final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();

ScanPage page(String id) =>
    ScanPage(id: id, sourceWidth: 1, sourceHeight: 1, corners: fullBounds(1, 1), renderWidth: 1, renderHeight: 1);

Future<(MemoryStore, FakeEngine)> seed({bool empty = false}) async {
  final store = MemoryStore();
  final repo = DocumentRepository(store);
  if (!empty) {
    for (final (id, title, pages) in [('a', 'Lease agreement', 3), ('b', 'Grocery receipt', 1)]) {
      final ps = [for (var i = 0; i < pages; i++) page('$id$i')];
      for (final p in ps) {
        for (final k in PageImage.values) {
          await repo.putPageImage(p.id, k, png);
        }
      }
      await repo.save(ScanDocument(
          id: id, title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026, 1, id == 'a' ? 2 : 1), pages: ps));
    }
  }
  return (store, FakeEngine(frameDetector: (_) => noPage));
}

List<Override> overrides(MemoryStore store, FakeEngine engine, {AppSettings? settings}) => [
      keyValueStoreProvider.overrideWithValue(store),
      scanEngineProvider.overrideWithValue(engine),
      if (settings != null) appSettingsProvider.overrideWith(() => AppSettingsNotifier(settings)),
      pageRendererProvider.overrideWith(
        (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (1, 1)),
      ),
    ];

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pump();
}

void main() {
  testWidgets('home without an account: actions, status and recent scans from storage', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await tester.pumpWidget(testApp(const HomePage(), overrides: overrides(store, engine)));
    await settle(tester);
    for (final label in ['Scan Document', 'Import Photos', 'Import PDF', 'View Documents', 'Settings', 'See all documents']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Scans are saved on this device'), findsOneWidget);
    expect(find.text('Recent scans'), findsOneWidget);
    expect(find.text('Lease agreement'), findsOneWidget);
    expect(find.text('Grocery receipt'), findsOneWidget);
    expect(find.text('On this device'), findsNWidgets(2), reason: 'guest scans are not backed up');
    // No sign-in anywhere on the home screen.
    expect(find.textContaining('Sign in'), findsNothing);
  });

  testWidgets('first launch with no scans: guidance instead of an empty list', (tester) async {
    final (store, engine) = (await tester.runAsync(() => seed(empty: true)))!;
    await tester.pumpWidget(testApp(const HomePage(), overrides: overrides(store, engine)));
    await settle(tester);
    expect(find.byKey(const ValueKey('first-time')), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('See all documents'), findsNothing);
  });

  testWidgets('documents: search titles, no-results state, clear', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await tester.pumpWidget(testApp(const DocumentsPage(), overrides: overrides(store, engine)));
    await settle(tester);
    expect(find.text('Lease agreement'), findsOneWidget);
    for (final label in ['Open', 'Rename', 'Export', 'Delete']) {
      expect(find.text(label), findsNWidgets(2), reason: '$label is a labelled button on each card');
    }
    await tester.enterText(find.byKey(const ValueKey('library-search')), 'receipt');
    await settle(tester);
    expect(find.text('Lease agreement'), findsNothing);
    expect(find.text('Grocery receipt'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('library-search')), 'zzz');
    await settle(tester);
    expect(find.text('No documents match “zzz”.'), findsOneWidget);
    await tester.tap(find.text('Clear search').last);
    await settle(tester);
    await settle(tester);
    expect(find.text('Lease agreement'), findsOneWidget);
  });

  testWidgets('settings: sign-in is optional, only under backup', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await tester.pumpWidget(testApp(const SettingsPage(), overrides: overrides(store, engine)));
    await settle(tester);
    expect(find.text('Simple Mode'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('open-backup')), 200);
    expect(find.text('Optional. Everything works without an account.'), findsOneWidget);
  });

  testWidgets('settings changes apply: Hindi', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await tester.pumpWidget(testApp(const HomePage(), overrides: overrides(store, engine), locale: const Locale('hi')));
    await settle(tester);
    expect(find.text('दस्तावेज़ स्कैन करें'), findsOneWidget);
    expect(find.text('हाल के स्कैन'), findsOneWidget);
  });

  testWidgets('first-run guide: next, back, skip', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await tester.pumpWidget(testApp(const OnboardingPage(),
        overrides: overrides(store, engine, settings: AppSettings(serverUrl: 'http://x', onboardingDone: false))));
    await settle(tester);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-next')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-skip')));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget, reason: 'skip goes straight to Home');
  });

  testWidgets('editor shows pages; rotate and rename update the document (no account)', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await tester.pumpWidget(testApp(const DocumentEditorPage(documentId: 'a'), overrides: overrides(store, engine)));
    await settle(tester);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Rotate'));
    await settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    final doc = (await tester.runAsync(() => DocumentRepository(store).get('a')))!;
    expect(doc.pages.first.edits.quarterTurns, 1);
    await tester.tap(find.byKey(const ValueKey('rename-doc')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rename-field')), 'Lease 2026');
    await tester.tap(find.text('Save'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Lease 2026'), findsOneWidget);
  });

  Future<void> openEditor(WidgetTester tester, MemoryStore store, FakeEngine engine) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(const DocumentEditorPage(documentId: 'a'), overrides: overrides(store, engine)));
    await settle(tester);
  }

  Future<List<String>> pageIds(WidgetTester tester, MemoryStore store) async =>
      [for (final p in (await tester.runAsync(() => DocumentRepository(store).get('a')))!.pages) p.id];

  testWidgets('editor: every page tool is labelled; no icon-only buttons or hidden menus', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await openEditor(tester, store, engine);
    for (final label in ['Rename', 'Export', 'Previous page', 'Next page', 'Add pages', 'Filters', 'Rotate', 'Crop',
        'Corners', 'Markup', 'Text', 'Retake', 'Move earlier', 'Move later', 'Delete page', 'Delete document']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(PopupMenuButton<Object>), findsNothing);
  });

  testWidgets('editor: Move later / Next page / Move earlier reorder without dragging', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await openEditor(tester, store, engine);
    await tester.tap(find.byKey(const ValueKey('move-later')));
    await settle(tester);
    expect(await pageIds(tester, store), ['a1', 'a0', 'a2']);
    expect(find.text('Page 2 of 3'), findsOneWidget, reason: 'follows the moved page');
    await tester.tap(find.byKey(const ValueKey('next-page')));
    await settle(tester);
    expect(find.text('Page 3 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('move-earlier')));
    await settle(tester);
    expect(await pageIds(tester, store), ['a1', 'a2', 'a0']);
  });

  testWidgets('editor: Delete page is immediate and Undo brings it back with its images', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await openEditor(tester, store, engine);
    await tester.tap(find.byKey(const ValueKey('next-page')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('delete-page')));
    await settle(tester);
    expect(await pageIds(tester, store), ['a0', 'a2']);
    expect(find.text('Page 2 deleted'), findsOneWidget);
    expect(await tester.runAsync(() => DocumentRepository(store).pageImage('a1', PageImage.render)), isNull);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await settle(tester);
    await settle(tester);
    expect(await pageIds(tester, store), ['a0', 'a1', 'a2']);
    expect(await tester.runAsync(() => DocumentRepository(store).pageImage('a1', PageImage.render)), isNotNull);
  });

  testWidgets('editor: Add pages is a labelled button that lists the choices', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await openEditor(tester, store, engine);
    await tester.tap(find.byKey(const ValueKey('add-pages')));
    await tester.pumpAndSettle();
    for (final label in ['Scan more', 'Import Photos', 'Import PDF or files']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('filters: preview cards, compare with original, apply shows progress', (tester) async {
    final (store, engine) = (await tester.runAsync(seed))!;
    await openEditor(tester, store, engine);
    await tester.tap(find.byKey(const ValueKey('tool-filters')));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    await tester.pumpAndSettle();
    for (final label in ['Original', 'Grayscale', 'Black & White', 'Magic Color']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('After'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compare-original')));
    await tester.pump();
    expect(find.text('Before'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('filter-bw')));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    final doc = (await tester.runAsync(() => DocumentRepository(store).get('a')))!;
    expect(doc.pages.first.edits.filter.wireName, 'bw');
    expect(find.text('Applying…'), findsNothing);
    expect(find.text('Apply Black & White to all pages'), findsOneWidget);
  });
}
