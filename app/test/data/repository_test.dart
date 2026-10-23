import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/storage/file_store.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/page_edits.dart';
import 'package:flutter_test/flutter_test.dart';

ScanDocument doc(String id, String title, {DateTime? updated, List<ScanPage> pages = const []}) => ScanDocument(
  id: id,
  title: title,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: updated ?? DateTime(2026, 1, 1),
  pages: pages,
);

const page = ScanPage(
  id: 'p1',
  sourceWidth: 100,
  sourceHeight: 200,
  corners: [Pt(1, 2), Pt(99, 2), Pt(99, 198), Pt(1, 198)],
  edits: PageEdits(filter: PageFilter.bw, quarterTurns: 1, crop: CropRect(0.1, 0.1, 0.5, 0.5)),
  revision: 3,
  renderWidth: 80,
  renderHeight: 160,
  ocrText: 'Invoice 42',
);

void main() {
  test('document JSON round trip', () {
    final d = doc('a', 'Taxes', pages: [page]).edit(title: 'Taxes 2026');
    final back = ScanDocument.fromJson(d.toJson());
    expect(back.title, 'Taxes 2026');
    expect(back.revision, 1);
    expect(back.needsSync, isTrue);
    expect(back.pages.single.edits, page.edits);
    expect(back.pages.single.corners, page.corners);
    expect(back.pages.single.ocrText, 'Invoice 42');
  });

  test('edit bumps revision; markSynced clears needsSync', () {
    final d = doc('a', 'x').edit(title: 'y');
    final synced = d.markSynced(remoteId: 'srv-1', revision: d.revision);
    expect(synced.needsSync, isFalse);
    expect(synced.edit(title: 'z').needsSync, isTrue);
  });

  group('repository', () {
    late DocumentRepository repo;
    setUp(() => repo = DocumentRepository(MemoryStore()));

    test('list is newest first and searchable by title and page text', () async {
      await repo.save(doc('a', 'Old receipt', updated: DateTime(2026, 1, 1)));
      await repo.save(doc('b', 'New contract', updated: DateTime(2026, 5, 1), pages: [page]));
      expect([for (final d in await repo.list()) d.id], ['b', 'a']);
      expect([for (final d in await repo.list(query: 'RECEIPT')) d.id], ['a']);
      expect([for (final d in await repo.list(query: 'invoice 42')) d.id], ['b']);
      expect(await repo.list(query: 'nothing'), isEmpty);
    });

    test('delete of an unsynced doc removes it and its images', () async {
      await repo.save(doc('a', 'x', pages: [page]));
      await repo.putPageImage('p1', PageImage.render, Uint8List.fromList([1]));
      await repo.delete((await repo.get('a'))!);
      expect(await repo.get('a'), isNull);
      expect(await repo.pageImage('p1', PageImage.render), isNull);
    });

    test('delete of a synced doc leaves a tombstone for sync', () async {
      await repo.save(doc('a', 'x').markSynced(remoteId: 'srv', revision: 0));
      await repo.delete((await repo.get('a'))!);
      expect((await repo.get('a'))!.deleted, isTrue);
      expect(await repo.list(), isEmpty);
      expect((await repo.listAll()).single.deleted, isTrue);
    });

    test('changes stream fires on save', () async {
      final events = <String>[];
      final sub = repo.changes.listen(events.add);
      await repo.save(doc('a', 'x'));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['a']);
      await sub.cancel();
    });
  });

  test('FileStore put/get/keys/deletePrefix', () async {
    final dir = await Directory.systemTemp.createTemp('docscanner_test');
    addTearDown(() => dir.delete(recursive: true));
    final s = FileStore(dir);
    await s.put('page/p1/source.jpg', Uint8List.fromList([1, 2, 3]));
    await s.put('page/p1/flat.jpg', Uint8List.fromList([4]));
    await s.put('doc/a.json', Uint8List.fromList([5]));
    expect(await s.get('page/p1/source.jpg'), [1, 2, 3]);
    expect((await s.keys('page/')).toSet(), {'page/p1/source.jpg', 'page/p1/flat.jpg'});
    await s.deletePrefix('page/p1/');
    expect(await s.keys('page/'), isEmpty);
    expect(await s.get('doc/a.json'), [5]);
    expect(() => s.get('../escape'), throwsArgumentError);
  });
}
