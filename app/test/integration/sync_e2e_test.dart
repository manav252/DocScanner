// End-to-end sync between two "devices" through the real backend.
//   cd ../backend && docker compose up -d --build
//   DOCSCANNER_E2E_API=http://localhost:8000 tool/host_test.sh test/integration
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/data/sync/sync_service.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/page_edits.dart';
import 'package:docscanner/services/api/api_client.dart';
import 'package:test/test.dart';

import '../imaging/fixtures.dart';

final api = Platform.environment['DOCSCANNER_E2E_API'];

class Device {
  Device(String url) : api = ApiClient(baseUrl: url);
  final store = MemoryStore();
  late final repo = DocumentRepository(store);
  final ApiClient api;
  late final sync = SyncService(api: api, repo: repo, store: store);

  Future<ScanDocument> doc(String id) async => (await repo.get(id))!;
}

final photo = File('${fixturesDir.path}/tilted_paper.jpg').readAsBytesSync();
final other = File('${fixturesDir.path}/low_contrast.jpg').readAsBytesSync();

Future<ScanPage> addPage(Device d, String id, Uint8List bytes) async {
  for (final k in [PageImage.source, PageImage.render, PageImage.thumb]) {
    await d.repo.putPageImage(id, k, bytes);
  }
  return ScanPage(id: id, sourceWidth: 1200, sourceHeight: 1600, corners: fullBounds(1200, 1600), renderWidth: 1200, renderHeight: 1600);
}

void main() {
  if (api == null) {
    test('sync e2e (set DOCSCANNER_E2E_API to run)', () {}, skip: 'backend not configured');
    return;
  }
  final email = 'e2e-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 20)}@example.com';
  final a = Device(api!), b = Device(api!);
  final t0 = DateTime.now().subtract(const Duration(hours: 1));

  test('A creates and pushes a document', () async {
    await a.api.register(email, 'correct horse battery');
    final pages = [await addPage(a, 'p1', photo), await addPage(a, 'p2', other)];
    await a.repo.save(ScanDocument(id: 'doc1', title: 'Lease', createdAt: t0, updatedAt: t0, pages: pages, backup: true).edit(now: t0));
    final r = await a.sync.sync();
    expect(r.pushed, 1);
    final d = await a.doc('doc1');
    expect(d.needsSync, isFalse);
    expect(d.serverVersion, 1);
  });

  test('B signs in and pulls it with its images', () async {
    await b.api.login(email, 'correct horse battery');
    final r = await b.sync.sync();
    expect(r.pulled, 1);
    final d = await b.doc('doc1');
    expect(d.title, 'Lease');
    expect(d.pages.map((p) => p.id), ['p1', 'p2']);
    expect(d.needsSync, isFalse);
    expect(await b.repo.pageImage('p2', PageImage.render), other);
    expect(await b.repo.pageImage('p1', PageImage.source), photo);
  });

  test('B edits (rename, remove a page, change a filter); A receives it', () async {
    final d = await b.doc('doc1');
    final p1 = d.pages.first.copyWith(edits: const PageEdits(filter: PageFilter.bw), revision: d.pages.first.revision + 1);
    await b.repo.save(d.edit(title: 'Lease 2026', pages: [p1], now: t0.add(const Duration(minutes: 1))));
    expect((await b.sync.sync()).pushed, 1);
    final r = await a.sync.sync();
    expect(r.pulled, 1);
    final ad = await a.doc('doc1');
    expect(ad.title, 'Lease 2026');
    expect(ad.pages.single.edits.filter, PageFilter.bw);
    expect(await a.repo.pageImage('p2', PageImage.render), isNull, reason: 'removed page images deleted');
  });

  test('concurrent edits: the newer edit wins on both devices', () async {
    final da = await a.doc('doc1'), db = await b.doc('doc1');
    await a.repo.save(da.edit(title: 'From A', now: t0.add(const Duration(minutes: 2))));
    await b.repo.save(db.edit(title: 'From B (newer)', now: t0.add(const Duration(minutes: 3))));
    await a.sync.sync(); // server = From A
    final rb = await b.sync.sync(); // conflict; B is newer -> overwrites
    expect(rb.conflicts, 1);
    await a.sync.sync();
    expect((await a.doc('doc1')).title, 'From B (newer)');
    expect((await b.doc('doc1')).title, 'From B (newer)');
    expect((await a.doc('doc1')).needsSync, isFalse);
  });

  test('an older concurrent edit loses to the server copy', () async {
    final da = await a.doc('doc1'), db = await b.doc('doc1');
    await b.repo.save(db.edit(title: 'B newest', now: t0.add(const Duration(minutes: 6))));
    await b.sync.sync();
    await a.repo.save(da.edit(title: 'A stale', now: t0.add(const Duration(minutes: 5))));
    await a.sync.sync();
    expect((await a.doc('doc1')).title, 'B newest');
  });

  test('retake on A re-uploads the photo; B downloads the new one', () async {
    final d = await a.doc('doc1');
    final p = d.pages.single;
    await a.repo.putPageImage(p.id, PageImage.source, other);
    final retaken = ScanPage(
      id: p.id,
      sourceWidth: p.sourceWidth,
      sourceHeight: p.sourceHeight,
      corners: p.corners,
      edits: p.edits,
      revision: p.revision + 1,
      sourceVersion: p.sourceVersion + 1,
    );
    await a.repo.save(d.edit(pages: [retaken], now: t0.add(const Duration(minutes: 7))));
    await a.sync.sync();
    await b.sync.sync();
    expect(await b.repo.pageImage(p.id, PageImage.source), other);
    expect((await b.doc('doc1')).pages.single.sourceVersion, p.sourceVersion + 1);
  });

  test('delete on B reaches A', () async {
    await b.repo.delete(await b.doc('doc1'));
    expect((await b.sync.sync()).deleted, 1);
    expect(await b.repo.get('doc1'), isNull);
    await a.sync.sync();
    expect(await a.repo.get('doc1'), isNull);
    expect(await a.repo.pageImage('p1', PageImage.render), isNull);
  });

  test('offline is reported as OfflineException and nothing is lost', () async {
    final off = Device('http://127.0.0.1:9');
    off.api.session = a.api.session;
    await off.repo.save(ScanDocument(id: 'x', title: 'Offline', createdAt: t0, updatedAt: t0, backup: true).edit());
    await expectLater(off.sync.sync(), throwsA(isA<OfflineException>()));
    expect((await off.repo.get('x'))!.needsSync, isTrue);
  });

  test('guest documents are never uploaded without consent', () async {
    final c = Device(api!);
    await c.api.register('guest-$email', 'correct horse battery');
    await c.repo.save(ScanDocument(id: 'guest', title: 'Made as guest', createdAt: t0, updatedAt: t0).edit());
    final r = await c.sync.sync();
    expect(r.pushed, 0);
    expect((await c.api.listDocuments())['documents'], isEmpty);
    // The user chooses "Upload now".
    final d = (await c.repo.get('guest'))!;
    await c.repo.save(d.edit(backup: true, now: d.updatedAt));
    expect((await c.sync.sync()).pushed, 1);
    expect([for (final x in (await c.api.listDocuments())['documents'] as List) (x as Map)['id']], ['guest']);
  });

  test('signing into another account does not copy documents there until asked', () async {
    await a.repo.save(ScanDocument(id: 'mine', title: 'Mine', createdAt: t0, updatedAt: t0, backup: true).edit());
    await a.sync.sync();
    await a.api.register('other-$email', 'correct horse battery');
    await a.sync.prepareForAccount(a.api.session!.userId);
    expect((await a.repo.get('mine'))!.backup, isFalse, reason: 'detached from the previous account');
    expect((await a.sync.sync()).pushed, 0);
    final d = (await a.repo.get('mine'))!;
    await a.repo.save(d.edit(backup: true, now: d.updatedAt));
    expect((await a.sync.sync()).pushed, 1);
    final list = await a.api.listDocuments();
    expect([for (final d in list['documents'] as List) (d as Map)['id']], ['mine']);
  });
}
