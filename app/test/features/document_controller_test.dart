import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/editor/document_controller.dart';
import 'package:docscanner/features/editor/export.dart';
import 'package:docscanner/features/library/import_flow.dart';
import 'package:docscanner/features/library/library_controller.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/page_edits.dart';
import 'package:docscanner/services/export/pdf_builder.dart';
import 'package:docscanner/services/import/import_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';

class FakeImporter extends ImportService {
  const FakeImporter();
  @override
  Stream<Uint8List> rasterizePdf(Uint8List pdf, {double dpi = 200}) async* {
    yield Uint8List.fromList([10]);
    yield Uint8List.fromList([11]);
  }
}

void main() {
  late FakeEngine engine;
  late MemoryStore store;
  late ProviderContainer c;
  late String id;

  setUp(() async {
    engine = FakeEngine(
      frameDetector: (_) => noPage,
      stillDetection: Detection(const [Pt(10, 10), Pt(90, 10), Pt(90, 130), Pt(10, 130)], found: true, score: .8),
      stillSize: (100, 140),
    );
    store = MemoryStore();
    c = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      scanEngineProvider.overrideWithValue(engine),
      importServiceProvider.overrideWithValue(const FakeImporter()),
      pageRendererProvider.overrideWith(
        (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (80, 120)),
      ),
    ]);
    addTearDown(c.dispose);
    id = (await c.read(libraryActionsProvider).createDocument(title: 'Test')).id;
    c.listen(documentProvider(id), (_, _) {});
    await c.read(documentProvider(id).future);
  });

  DocumentController ctrl() => c.read(documentProvider(id).notifier);
  Future<ScanDocument> saved() async => (await c.read(documentRepositoryProvider).get(id))!;

  Future<void> addPages(int n) async {
    for (var i = 0; i < n; i++) {
      await ctrl().addImage(Uint8List.fromList([i]), 100, 140, fullBounds(100, 140));
    }
  }

  test('adding a page stores source, flat, render and thumb', () async {
    await addPages(1);
    final d = await saved();
    final p = d.pages.single;
    for (final k in PageImage.values) {
      expect(store.data.containsKey(DocumentRepository.pageImageKey(p.id, k)), isTrue, reason: k.name);
    }
    expect((p.renderWidth, p.renderHeight), (80, 120));
    expect(p.edits.filter, PageFilter.magicColor);
    expect(d.revision, 1);
  });

  test('reorder, rotate, filter, crop, delete', () async {
    await addPages(3);
    final ids = [for (final p in (await saved()).pages) p.id];
    await ctrl().reorder(0, 2);
    expect([for (final p in (await saved()).pages) p.id], [ids[1], ids[2], ids[0]]);

    await ctrl().setCrop(ids[1], const CropRect(0, 0, 0.5, 0.5));
    await ctrl().rotate(ids[1]);
    var p = (await saved()).pages.firstWhere((p) => p.id == ids[1]);
    expect(p.edits.quarterTurns, 1);
    expect(p.edits.crop, const CropRect(0.5, 0, 0.5, 0.5), reason: 'crop follows the rotation');

    final rev = p.revision;
    await ctrl().setFilter(ids[1], PageFilter.bw);
    p = (await saved()).pages.firstWhere((p) => p.id == ids[1]);
    expect(p.edits.filter, PageFilter.bw);
    expect(p.revision, rev + 1, reason: 're-rendered');
    expect(engine.processed.last.filter, PageFilter.original, reason: 'thumb rendered from the result');

    await ctrl().deletePage(ids[2]);
    final d = await saved();
    expect(d.pages.map((p) => p.id), [ids[1], ids[0]]);
    expect(store.data.keys.where((k) => k.contains(ids[2])), isEmpty);
  });

  test('apply filter to all pages', () async {
    await addPages(2);
    await ctrl().applyFilterToAll(PageFilter.grayscale);
    expect((await saved()).pages.every((p) => p.edits.filter == PageFilter.grayscale), isTrue);
  });

  test('setCorners re-flattens and resets crop', () async {
    await addPages(1);
    final pid = (await saved()).pages.single.id;
    await ctrl().setCrop(pid, const CropRect(0.2, 0.2, 0.5, 0.5));
    await ctrl().setCorners(pid, const [Pt(5, 5), Pt(95, 5), Pt(95, 135), Pt(5, 135)]);
    final p = (await saved()).pages.single;
    expect(p.corners.first, const Pt(5, 5));
    expect(p.edits.crop.isFull, isTrue);
    expect(engine.warpedCorners!.first, const Pt(5, 5));
  });

  test('retake replaces the photo but keeps position and filter', () async {
    await addPages(2);
    final first = (await saved()).pages.first;
    await ctrl().setFilter(first.id, PageFilter.bw);
    await ctrl().replaceImage(first.id, Uint8List.fromList([9, 9]), 100, 140, fullBounds(100, 140));
    final d = await saved();
    expect(d.pages.first.id, first.id);
    expect(d.pages.first.edits.filter, PageFilter.bw);
    expect(store.data[DocumentRepository.pageImageKey(first.id, PageImage.source)], [9, 9]);
  });

  test('rename', () async {
    await ctrl().rename('  Lease  ');
    expect((await saved()).title, 'Lease');
    await ctrl().rename('   ');
    expect((await saved()).title, 'Lease');
  });

  test('import: photos are detected + Magic Color, PDF pages are added as-is', () async {
    final n = await c.read(importFlowProvider).importFiles(id, [
      ImportedFile('a.jpg', Uint8List.fromList([1, 2])),
      ImportedFile('b.pdf', Uint8List.fromList('%PDF-1.7'.codeUnits)),
    ]);
    expect(n, 3);
    final pages = (await saved()).pages;
    expect(pages[0].corners.first, const Pt(10, 10));
    expect(pages[0].edits.filter, PageFilter.magicColor);
    expect(pages[1].edits.filter, PageFilter.original);
    expect(pages[2].corners, fullBounds(100, 140), reason: 'PDF page uses its own (normalised) bounds');
  });

  test('export PDF and JPGs', () async {
    // Real JPEGs so the PDF writer can read their size.
    final jpg = File('${fixturesDir.path}/tilted_paper.jpg').readAsBytesSync();
    await addPages(2);
    final repo = c.read(documentRepositoryProvider);
    final d = await saved();
    for (final p in d.pages) {
      await repo.putPageImage(p.id, PageImage.render, jpg);
    }
    final pdf = await buildExport(repo, d, format: ExportFormat.pdf, pageSize: PdfPageSize.a4);
    expect(pdf.single.name, 'Test.pdf');
    final text = String.fromCharCodes(pdf.single.bytes);
    expect(text.startsWith('%PDF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);

    final jpgs = await buildExport(repo, d, format: ExportFormat.jpg);
    expect([for (final f in jpgs) f.name], ['Test - 1.jpg', 'Test - 2.jpg']);
  });

  test('library search sees new documents', () async {
    final sub = c.listen(libraryProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(libraryActionsProvider).createDocument(title: 'Receipt Oct');
    c.read(libraryQueryProvider.notifier).set('receipt');
    final list = await c.read(libraryProvider.future);
    expect(list.map((d) => d.title), ['Receipt Oct']);
  });
}
