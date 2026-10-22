import 'dart:io';

import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/editor/document_editor_page.dart';
import 'package:docscanner/features/library/library_page.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';

final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();

ScanPage page(String id) => ScanPage(id: id, sourceWidth: 1, sourceHeight: 1, corners: fullBounds(1, 1), renderWidth: 1, renderHeight: 1);

Future<(MemoryStore, FakeEngine)> seed() async {
  final store = MemoryStore();
  final repo = DocumentRepository(store);
  for (final (id, title, pages) in [('a', 'Lease agreement', 3), ('b', 'Grocery receipt', 1)]) {
    final ps = [for (var i = 0; i < pages; i++) page('$id$i')];
    for (final p in ps) {
      for (final k in PageImage.values) {
        await repo.putPageImage(p.id, k, png);
      }
    }
    await repo.save(ScanDocument(id: id, title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026, 1, id == 'a' ? 2 : 1), pages: ps));
  }
  return (store, FakeEngine(frameDetector: (_) => noPage));
}

Widget app(MemoryStore store, FakeEngine engine, Widget home) => ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        scanEngineProvider.overrideWithValue(engine),
        pageRendererProvider.overrideWith(
          (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (1, 1)),
        ),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets('library lists documents and filters by search', (tester) async {
    final (store, engine) = await tester.runAsync(seed) as (MemoryStore, FakeEngine);
    await tester.pumpWidget(app(store, engine, const LibraryPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Lease agreement'), findsOneWidget);
    expect(find.text('Grocery receipt'), findsOneWidget);
    expect(find.textContaining('3 pages'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('library-search')), 'receipt');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Lease agreement'), findsNothing);
    expect(find.text('Grocery receipt'), findsOneWidget);
  });

  testWidgets('empty library shows Scan and Import', (tester) async {
    await tester.pumpWidget(app(MemoryStore(), FakeEngine(frameDetector: (_) => noPage), const LibraryPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('No scans yet'), findsOneWidget);
  });

  testWidgets('editor shows pages; rotate and rename update the document', (tester) async {
    final (store, engine) = await tester.runAsync(seed) as (MemoryStore, FakeEngine);
    await tester.pumpWidget(app(store, engine, const DocumentEditorPage(documentId: 'a')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text('Lease agreement'), findsOneWidget);

    await tester.tap(find.text('Rotate'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    final repo = DocumentRepository(store);
    final doc = (await tester.runAsync(() => repo.get('a')))!;
    expect(doc.pages.first.edits.quarterTurns, 1);

    await tester.tap(find.text('Lease agreement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rename-field')), 'Lease 2026');
    await tester.tap(find.text('Save'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Lease 2026'), findsOneWidget);
  });
}
