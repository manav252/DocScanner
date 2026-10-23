// Backup without an account: export every document as a ZIP, import it on a
// fresh device or over existing documents.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docscanner/core/cancel.dart';
import 'package:docscanner/data/backup.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/markup.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

ScanPage page(String id, {List<MarkupItem> markup = const []}) => ScanPage(
  id: id,
  sourceWidth: 10,
  sourceHeight: 10,
  corners: fullBounds(10, 10),
  renderWidth: 10,
  renderHeight: 10,
  ocrText: 'text of $id',
  markup: markup,
);

Future<(MemoryStore, DocumentRepository)> device({int docs = 2, DateTime? updated}) async {
  final store = MemoryStore();
  final repo = DocumentRepository(store);
  for (var d = 0; d < docs; d++) {
    final pages = [page('d$d-p0'), page('d$d-p1', markup: [const TextMarkup(id: 'm', text: 'Paid', x: .5, y: .5)])];
    for (final p in pages) {
      for (final f in ['source', 'flat', 'render', 'thumb']) {
        await store.put('page/${p.id}/$f.jpg', bytes('$f of ${p.id}'));
      }
      await store.put('page/${p.id}/ocr.json', bytes('{"text":"x","lines":[]}'));
    }
    await repo.save(
      ScanDocument(
        id: 'd$d',
        title: 'Document $d',
        createdAt: DateTime(2026),
        updatedAt: updated ?? DateTime(2026, 2, d + 1),
        pages: pages,
        remoteId: d == 0 ? 'server-0' : null,
        syncedRevision: d == 0 ? 3 : -1,
      ),
    );
  }
  return (store, repo);
}

void main() {
  test('export: every document, its pages (no flattened copy) and a manifest; stored, not deflated', () async {
    final (store, repo) = await device();
    final zip = await BackupService(repo, store).exportAll();
    final a = ZipDecoder().decodeBytes(zip);
    final names = a.files.map((f) => f.name).toSet();
    expect(names, contains(BackupService.manifestName));
    expect(names, containsAll(['documents/d0.json', 'documents/d1.json', 'pages/d1-p1/render.jpg', 'pages/d1-p1/ocr.json']));
    expect(names.where((n) => n.endsWith('flat.jpg')), isEmpty);
    expect(utf8.decode(a.find('pages/d0-p0/source.jpg')!.content), 'source of d0-p0');
    final m = jsonDecode(utf8.decode(a.find(BackupService.manifestName)!.content)) as Map<String, dynamic>;
    expect(m['format'], 1);
    expect(m['documents'], ['d1', 'd0']); // newest first
  });

  test('import on a new device: documents, text, markup and images come back, kept on the device', () async {
    final (store, repo) = await device();
    final zip = await BackupService(repo, store).exportAll();

    final fresh = MemoryStore();
    final freshRepo = DocumentRepository(fresh);
    final r = await BackupService(freshRepo, fresh).importZip(zip);
    expect((r.added, r.updated, r.skipped), (2, 0, 0));
    final docs = await freshRepo.list();
    expect(docs.map((d) => d.title), ['Document 1', 'Document 0']);
    final d0 = docs.firstWhere((d) => d.id == 'd0');
    expect(d0.remoteId, isNull, reason: 'not tied to another account');
    expect(d0.backup, isFalse);
    expect(d0.pages[0].ocrText, 'text of d0-p0');
    expect((d0.pages[1].markup.single as TextMarkup).text, 'Paid');
    expect(utf8.decode((await freshRepo.pageImage('d0-p1', PageImage.render))!), 'render of d0-p1');
    expect(await freshRepo.pageImage('d0-p1', PageImage.flat), isNull, reason: 'rebuilt on the next edit');
  });

  test('import over existing documents: newer copies replace older ones, the rest is skipped', () async {
    final (store, repo) = await device(updated: DateTime(2026, 5));
    final zip = await BackupService(repo, store).exportAll();

    final (other, otherRepo) = await device(updated: DateTime(2026, 1)); // older copies, d0 synced
    await otherRepo.save((await otherRepo.get('d1'))!.edit(title: 'Newer here', now: DateTime(2026, 9)));
    final r = await BackupService(otherRepo, other).importZip(zip);
    expect((r.added, r.updated, r.skipped), (0, 1, 1));
    final d0 = (await otherRepo.get('d0'))!;
    expect(d0.updatedAt, DateTime(2026, 5));
    expect(d0.remoteId, 'server-0', reason: 'same server document, no duplicate');
    expect(d0.needsSync, isTrue, reason: 'the restored version gets backed up');
    expect((await otherRepo.get('d1'))!.title, 'Newer here');
  });

  test('not a backup: clear errors, nothing changed', () async {
    final (store, repo) = await device(docs: 0);
    final svc = BackupService(repo, store);
    await expectLater(svc.importZip(bytes('hello')), throwsA(isA<BackupFormatException>()));
    final other = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.string('notes.txt', 'hi')));
    await expectLater(
      svc.importZip(other),
      throwsA(isA<BackupFormatException>().having((e) => e.message, 'message', contains('not a DocScanner backup'))),
    );
    expect(store.data, isEmpty);
  });

  test('cancel stops the export', () async {
    final (store, repo) = await device();
    final cancel = CancelToken()..cancel();
    await expectLater(BackupService(repo, store).exportAll(cancel: cancel), throwsA(isA<Cancelled>()));
  });
}
