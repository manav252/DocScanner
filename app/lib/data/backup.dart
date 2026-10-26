// "Export all documents" / "Import backup": one ZIP with every document, so a
// guest (no account) can keep a copy or move to another device.
//
//   docscanner-backup.json            {format, app, created, documents}
//   documents/<docId>.json            the document (title, pages, edits, markup, text)
//   pages/<pageId>/<file>             source.jpg, render.jpg, thumb.jpg, ocr.json
//
// The flattened image is left out: it is rebuilt from the photo on the next edit.
// Files are stored, not deflated: JPEGs do not compress further.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/cancel.dart';
import 'document_repository.dart';
import 'models.dart';
import 'storage/key_value_store.dart';

class BackupImportResult {
  const BackupImportResult({this.added = 0, this.updated = 0, this.skipped = 0});

  /// New documents, newer copies that replaced older ones, documents already up to date here.
  final int added, updated, skipped;
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackupService {
  BackupService(this._repo, this._store);
  final DocumentRepository _repo;
  final KeyValueStore _store;

  static const format = 1;
  static const manifestName = 'docscanner-backup.json';
  static const _pageFiles = ['source.jpg', 'render.jpg', 'thumb.jpg', 'ocr.json'];

  /// Every visible document as a ZIP.
  Future<Uint8List> exportAll({CancelToken? cancel, void Function(int done, int total)? onProgress}) async {
    final docs = await _repo.list();
    final archive = Archive();
    for (final (i, d) in docs.indexed) {
      cancel?.check();
      onProgress?.call(i, docs.length);
      archive.add(_stored('documents/${d.id}.json', utf8.encode(jsonEncode(d.toJson()))));
      for (final p in d.pages) {
        for (final f in _pageFiles) {
          final bytes = await _store.get('page/${p.id}/$f');
          if (bytes != null) archive.add(_stored('pages/${p.id}/$f', bytes));
        }
      }
    }
    archive.add(
      _stored(
        manifestName,
        utf8.encode(
          jsonEncode({
            'format': format,
            'app': 'DocScanner',
            'created': DateTime.now().toUtc().toIso8601String(),
            'documents': [for (final d in docs) d.id],
          }),
        ),
      ),
    );
    onProgress?.call(docs.length, docs.length);
    return ZipEncoder().encodeBytes(archive);
  }

  static ArchiveFile _stored(String name, List<int> bytes) =>
      ArchiveFile.bytes(name, bytes)..compression = CompressionType.none;

  /// Restore documents from [zip]. A document already on this device is
  /// replaced only if the backup's copy is newer. Imported documents stay on
  /// this device (they are not backed up to an account until the user chooses to).
  Future<BackupImportResult> importZip(
    Uint8List zip, {
    CancelToken? cancel,
    void Function(int, int)? onProgress,
  }) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip);
    } catch (_) {
      throw const BackupFormatException('This is not a DocScanner backup (not a ZIP file).');
    }
    final manifest = archive.find(manifestName);
    if (manifest == null) throw const BackupFormatException('This ZIP is not a DocScanner backup.');
    final m = jsonDecode(utf8.decode(manifest.content)) as Map<String, dynamic>;
    if ((m['format'] as int? ?? 0) > format) {
      throw const BackupFormatException('This backup was made by a newer version of DocScanner.');
    }
    final ids = (m['documents'] as List).cast<String>();
    var added = 0, updated = 0, skipped = 0;
    for (final (i, id) in ids.indexed) {
      cancel?.check();
      onProgress?.call(i, ids.length);
      final entry = archive.find('documents/$id.json');
      if (entry == null) continue;
      final incoming = ScanDocument.fromJson(jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>);
      final local = await _repo.get(id);
      if (local != null && !local.deleted && !incoming.updatedAt.isAfter(local.updatedAt)) {
        skipped++;
        continue;
      }
      // Page files first, so a document never points at missing images.
      for (final p in incoming.pages) {
        for (final f in _pageFiles) {
          final file = archive.find('pages/${p.id}/$f');
          if (file != null) await _store.put('page/${p.id}/$f', file.content);
        }
        await _store.delete('page/${p.id}/flat.jpg'); // stale if the photo changed
      }
      if (local == null || local.deleted) {
        await _repo.save(
          ScanDocument(
            id: incoming.id,
            title: incoming.title,
            createdAt: incoming.createdAt,
            updatedAt: incoming.updatedAt,
            pages: incoming.pages,
            revision: incoming.revision,
            backup: false,
            idCard: incoming.idCard,
            idFields: incoming.idFields,
          ),
        );
        added++;
      } else {
        // Newer copy of a document this device knows: keep its sync identity so
        // backup updates the same server document instead of making a copy.
        await _repo.save(
          ScanDocument(
            id: local.id,
            title: incoming.title,
            createdAt: incoming.createdAt,
            updatedAt: incoming.updatedAt,
            pages: incoming.pages,
            revision: local.revision + 1,
            remoteId: local.remoteId,
            syncedRevision: local.syncedRevision,
            serverVersion: local.serverVersion,
            backup: local.backup,
            idCard: incoming.idCard ?? local.idCard,
            idFields: incoming.idFields.isEmpty ? local.idFields : incoming.idFields,
            idBackupApproved: local.idBackupApproved,
          ),
        );
        for (final old in local.pages) {
          if (!incoming.pages.any((p) => p.id == old.id)) await _repo.deletePageImages(old.id);
        }
        updated++;
      }
    }
    onProgress?.call(ids.length, ids.length);
    return BackupImportResult(added: added, updated: updated, skipped: skipped);
  }
}
