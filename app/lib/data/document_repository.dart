// Local, offline-first document library.
//   doc/<id>.json               document metadata (title, pages, edits, sync state)
//   page/<pageId>/<kind>.jpg    page images (see PageImage)
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';
import 'storage/key_value_store.dart';

class DocumentRepository {
  DocumentRepository(this._store);
  final KeyValueStore _store;
  final _changes = StreamController<String>.broadcast();

  /// Emits a document id whenever that document is saved or deleted.
  Stream<String> get changes => _changes.stream;

  static String _docKey(String id) => 'doc/$id.json';
  static String pageImageKey(String pageId, PageImage kind) => 'page/$pageId/${kind.name}.jpg';

  /// Every document, including tombstones (for sync).
  Future<List<ScanDocument>> listAll() async {
    final out = <ScanDocument>[];
    for (final k in await _store.keys('doc/')) {
      final bytes = await _store.get(k);
      if (bytes == null) continue;
      try {
        out.add(ScanDocument.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>));
      } on FormatException {
        // Skip a corrupt entry rather than breaking the whole library.
      }
    }
    return out;
  }

  /// Visible documents, newest first, optionally filtered by [query]
  /// (case-insensitive match on the title or recognised page text).
  Future<List<ScanDocument>> list({String query = ''}) async {
    final q = query.trim().toLowerCase();
    final docs = [
      for (final d in await listAll())
        if (!d.deleted &&
            (q.isEmpty ||
                d.title.toLowerCase().contains(q) ||
                d.pages.any((p) => p.ocrText?.toLowerCase().contains(q) ?? false)))
          d,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return docs;
  }

  Future<ScanDocument?> get(String id) async {
    final bytes = await _store.get(_docKey(id));
    return bytes == null ? null : ScanDocument.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
  }

  Future<void> save(ScanDocument doc) async {
    await _store.put(_docKey(doc.id), Uint8List.fromList(utf8.encode(jsonEncode(doc.toJson()))));
    _changes.add(doc.id);
  }

  /// Delete locally. A synced document becomes a tombstone so the deletion
  /// reaches the server; page images are removed either way.
  Future<void> delete(ScanDocument doc) async {
    for (final p in doc.pages) {
      await deletePageImages(p.id);
    }
    if (doc.remoteId != null) {
      await save(doc.edit(deleted: true, pages: const []));
    } else {
      await purge(doc.id);
    }
  }

  /// Remove a document record entirely (after its deletion has been synced).
  Future<void> purge(String id) async {
    await _store.delete(_docKey(id));
    _changes.add(id);
  }

  Future<Uint8List?> pageImage(String pageId, PageImage kind) => _store.get(pageImageKey(pageId, kind));

  Future<void> putPageImage(String pageId, PageImage kind, Uint8List bytes) =>
      _store.put(pageImageKey(pageId, kind), bytes);

  Future<void> deletePageImages(String pageId) => _store.deletePrefix('page/$pageId/');

  /// OCR line boxes (JSON) for the searchable-PDF text layer; text lives in the page.
  Future<Uint8List?> pageOcr(String pageId) => _store.get('page/$pageId/ocr.json');

  Future<void> putPageOcr(String pageId, Uint8List json) => _store.put('page/$pageId/ocr.json', json);

  void dispose() => _changes.close();
}
