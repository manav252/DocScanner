// Instant delete with Undo (and rollback when the delete fails), thumbnails
// that never spin forever, and a 30-page document.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/data/thumbnails.dart';
import 'package:docscanner/features/common/collapsible.dart';
import 'package:docscanner/features/common/page_image.dart';
import 'package:docscanner/features/library/documents_page.dart';
import 'package:docscanner/features/library/library_controller.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';
import '../support/test_app.dart';

final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();

/// Counts reads of document records; can refuse to delete them.
class TestStore extends MemoryStore {
  int docReads = 0;
  bool failDocDeletes = false;
  final hang = <String>{};

  @override
  Future<Uint8List?> get(String key) {
    if (key.startsWith('doc/')) docReads++;
    if (hang.any(key.startsWith)) return Completer<Uint8List?>().future; // storage that never answers
    return super.get(key);
  }

  @override
  Future<void> delete(String key) async {
    if (failDocDeletes && key.startsWith('doc/')) throw StateError('disk full');
    return super.delete(key);
  }
}

ScanPage page(String id) =>
    ScanPage(id: id, sourceWidth: 1, sourceHeight: 1, corners: fullBounds(1, 1), renderWidth: 1, renderHeight: 1);

Future<TestStore> seed({int docs = 3, int bigPages = 3, Set<PageImage> kinds = const {...PageImage.values}}) async {
  final store = TestStore();
  final repo = DocumentRepository(store);
  for (var d = 0; d < docs; d++) {
    final pages = [for (var p = 0; p < (d == 0 ? bigPages : 1); p++) page('d$d-p$p')];
    for (final p in pages) {
      for (final k in kinds) {
        await repo.putPageImage(p.id, k, png);
      }
    }
    await repo.save(
      ScanDocument(
        id: 'd$d',
        title: d == 0 ? 'CWT' : 'Doc $d',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026, 1, 10 - d),
        pages: pages,
      ),
    );
  }
  return store;
}

List<Override> overrides(MemoryStore store, FakeEngine engine) => [
  keyValueStoreProvider.overrideWithValue(store),
  scanEngineProvider.overrideWithValue(engine),
  pageRendererProvider.overrideWith(
    (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (1, 1)),
  ),
];

Future<void> settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Folding away, or already dropped from the list.
bool hidden(WidgetTester tester, String docId) {
  final f = find.byKey(ValueKey(docId));
  return f.evaluate().isEmpty || tester.widget<Collapsible>(f).hidden;
}

Future<void> openDocuments(WidgetTester tester, TestStore store) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(const DocumentsPage(), overrides: overrides(store, FakeEngine(frameDetector: (_) => noPage))),
  );
  await settle(tester);
}

Future<List<String>> ids(WidgetTester tester, TestStore store) async => [
  for (final d in (await tester.runAsync(() => DocumentRepository(store).list()))!) d.id,
];

void main() {
  group('delete', () {
    testWidgets('the card goes at once; Undo brings it back; nothing was deleted', (tester) async {
      final store = (await tester.runAsync(seed))!;
      await openDocuments(tester, store);
      await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
      await tester.pump(); // one frame: no dialog, no waiting for storage
      expect(hidden(tester, 'd0'), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Document deleted'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400)); // snackbar slides in
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(hidden(tester, 'd0'), isFalse);
      await tester.pump(const Duration(seconds: 6)); // past the Undo window
      await settle(tester);
      expect(await ids(tester, store), contains('d0'));
      expect(store.data.keys.where((k) => k.startsWith('page/d0-')), isNotEmpty);
    });

    testWidgets('without Undo, the files are removed after 5 s in the background', (tester) async {
      final store = (await tester.runAsync(seed))!;
      await openDocuments(tester, store);
      await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
      expect(await ids(tester, store), contains('d0'), reason: 'still undoable');
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(await ids(tester, store), isNot(contains('d0')));
      expect(store.data.keys.where((k) => k.startsWith('page/d0-')), isEmpty);
      expect(find.text('CWT'), findsNothing);
    });

    testWidgets('if the delete fails, the card comes back with an error', (tester) async {
      final store = (await tester.runAsync(seed))!..failDocDeletes = true;
      await openDocuments(tester, store);
      await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
      await tester.pump();
      expect(hidden(tester, 'd0'), isTrue);
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
      expect(hidden(tester, 'd0'), isFalse);
      await tester.pump(const Duration(seconds: 1)); // the first snackbar leaves, the error one comes in
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Couldn’t delete “CWT”. It has been put back.'), findsOneWidget);
      // The record failed first, so no page image was removed.
      expect(store.data.keys.where((k) => k.startsWith('page/d0-')), hasLength(PageImage.values.length * 3));
    });
  });

  group('thumbnails', () {
    test('missing thumbnail is rebuilt from the page and cached', () async {
      final store = await seed(kinds: {PageImage.source, PageImage.render});
      final engine = FakeEngine(frameDetector: (_) => noPage);
      final svc = ThumbnailService(DocumentRepository(store), engine);
      final t = await svc.thumb('d0-p0', 0);
      expect(t, isNotNull);
      expect(store.data[DocumentRepository.pageImageKey('d0-p0', PageImage.thumb)], isNotNull, reason: 'stored');
      expect(engine.processed, hasLength(1));
      final again = await svc.thumb('d0-p0', 0);
      expect(identical(again, t), isTrue, reason: 'served from memory, same bytes (image cache hit)');
    });

    test('page without any image: null, not an endless wait', () async {
      final store = await seed(kinds: const {});
      final svc = ThumbnailService(DocumentRepository(store), FakeEngine(frameDetector: (_) => noPage));
      expect(await svc.thumb('d0-p0', 0), isNull);
    });

    test('storage that never answers times out', () async {
      final store = (await seed())..hang.add('page/d0-p0/thumb');
      final svc = ThumbnailService(
        DocumentRepository(store),
        FakeEngine(frameDetector: (_) => noPage),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(svc.thumb('d0-p0', 0), throwsA(isA<TimeoutException>()));
    });

    test('repair makes missing thumbnails and removes leftovers of an interrupted delete', () async {
      final store = await seed(kinds: {PageImage.render});
      final repo = DocumentRepository(store);
      // A delete that stopped after the record was removed (journal still lists the pages).
      store.failDocDeletes = false;
      await repo.putPageImage('gone-p0', PageImage.render, png);
      await store.put('app/pages-to-delete.json', Uint8List.fromList('["gone-p0"]'.codeUnits));
      // A page being saved right now is not in the journal: never touched.
      await repo.putPageImage('saving-p0', PageImage.source, png);
      final (made, removed) = await ThumbnailService(repo, FakeEngine(frameDetector: (_) => noPage)).repair();
      expect(made, 5); // 3 pages of CWT + 2 one-page documents
      expect(removed, 1);
      expect(store.data.keys.where((k) => k.startsWith('page/gone-p0/')), isEmpty);
      expect(store.data.keys.where((k) => k.startsWith('page/saving-p0/')), isNotEmpty);
    });

    testWidgets('a card whose preview cannot load shows an icon and the name, no spinner', (tester) async {
      final store = (await tester.runAsync(() => seed(kinds: const {})))!;
      final semantics = tester.ensureSemantics();
      await openDocuments(tester, store);
      await settle(tester, 10);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Preview not available')), findsWidgets);
      expect(
        find.descendant(of: find.byType(StoredPageImage), matching: find.text('CWT')),
        findsOneWidget,
        reason: 'the placeholder names the document',
      );
      semantics.dispose();
    });
  });

  group('large documents', () {
    testWidgets('30-page document: list shows it; a change re-reads one record, not the library', (tester) async {
      final store = (await tester.runAsync(() => seed(docs: 20, bigPages: 30)))!;
      await openDocuments(tester, store);
      expect(find.text('30 pages'), findsOneWidget);
      final c = ProviderScope.containerOf(tester.element(find.byType(DocumentsPage)));
      store.docReads = 0;
      await tester.runAsync(() async {
        await c.read(libraryActionsProvider).rename((await DocumentRepository(store).get('d5'))!, 'Renamed');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);
      expect(find.text('Renamed'), findsOneWidget);
      // rename reads d5 once, the list re-reads d5 once: not all 20 documents.
      expect(store.docReads, lessThanOrEqualTo(3));
    });

    test('deleting a 30-page document removes all 120 page files', () async {
      final store = await seed(docs: 1, bigPages: 30);
      final repo = DocumentRepository(store);
      final sw = Stopwatch()..start();
      await repo.delete((await repo.get('d0'))!);
      expect(store.data.keys.where((k) => k.startsWith('page/')), isEmpty);
      expect(await repo.orphanPageIds(), isEmpty, reason: 'journal cleared');
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });
}
