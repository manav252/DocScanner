// Offline-first sync between the local library and the backend.
//
// The library is always the source of truth for the UI; sync runs in the
// background whenever the user is signed in and the server is reachable.
//
//   push:  for each document with local changes (revision != syncedRevision)
//            1. upload changed page images (source / render / thumb)
//            2. PUT metadata with base_version = the server version we last saw
//            3. on 409 (someone else changed it) the newer edit wins (updatedAt)
//          deleted documents -> DELETE, then forget them locally
//   pull:  GET /documents?since=<cursor>; apply every server change that does
//          not collide with a newer local edit; download page images.
import 'dart:convert';
import 'dart:typed_data';

import '../../imaging/geometry.dart';
import '../../imaging/page_edits.dart';
import '../../services/api/api_client.dart';
import '../document_repository.dart';
import '../models.dart';
import '../storage/key_value_store.dart';

/// What sync has already uploaded/downloaded, persisted next to the library.
class SyncState {
  SyncState({this.userId, this.cursor = 0, Map<String, (int, int)>? pages}) : pages = pages ?? {};

  /// Account this state belongs to (a different sign-in resets it).
  String? userId;

  /// Server change cursor (GET /documents?since=).
  int cursor;

  /// pageId -> (render revision, source version) present on the server.
  final Map<String, (int, int)> pages;

  static const key = 'sync/state.json';

  Map<String, Object?> toJson() => {
        'userId': userId,
        'cursor': cursor,
        'pages': {for (final e in pages.entries) e.key: [e.value.$1, e.value.$2]},
      };

  static SyncState fromJson(Map<String, dynamic> j) => SyncState(
        userId: j['userId'] as String?,
        cursor: j['cursor'] as int? ?? 0,
        pages: {
          for (final e in ((j['pages'] as Map?) ?? {}).entries)
            e.key as String: ((e.value as List)[0] as int, (e.value as List)[1] as int),
        },
      );
}

class SyncReport {
  int pushed = 0, pulled = 0, deleted = 0, conflicts = 0;
  @override
  String toString() => 'pushed $pushed, pulled $pulled, deleted $deleted, conflicts $conflicts';
}

class SyncService {
  SyncService({required this.api, required this.repo, required this.store});
  final ApiClient api;
  final DocumentRepository repo;
  final KeyValueStore store;

  static const _kinds = {PageImage.source: 'source', PageImage.render: 'render', PageImage.thumb: 'thumb'};

  Future<SyncState> _loadState() async {
    final b = await store.get(SyncState.key);
    return b == null ? SyncState() : SyncState.fromJson(jsonDecode(utf8.decode(b)) as Map<String, dynamic>);
  }

  Future<void> _saveState(SyncState s) =>
      store.put(SyncState.key, Uint8List.fromList(utf8.encode(jsonEncode(s.toJson()))));

  /// One full push + pull. Throws [OfflineException] / [ApiException].
  Future<SyncReport> sync() async {
    final session = api.session;
    if (session == null) throw const ApiException(401, 'Not signed in');
    final state = await _loadState();
    if (state.userId != session.userId) await _adoptAccount(state, session.userId);
    final report = SyncReport();
    await _push(state, report);
    await _pull(state, report);
    return report;
  }

  /// A different account signed in: everything local is new to it.
  Future<void> _adoptAccount(SyncState state, String userId) async {
    for (final d in await repo.listAll()) {
      if (d.deleted) {
        await repo.purge(d.id);
      } else if (d.remoteId != null || d.syncedRevision != -1) {
        await repo.save(d.unsynced());
      }
    }
    state
      ..userId = userId
      ..cursor = 0
      ..pages.clear();
    await _saveState(state);
  }

  // ---------------- push ----------------

  Future<void> _push(SyncState state, SyncReport report) async {
    for (final doc in await repo.listAll()) {
      if (!doc.needsSync) continue;
      if (doc.deleted) {
        // Deletion wins over concurrent remote edits.
        if (doc.remoteId != null) await api.deleteDocument(doc.id);
        await repo.purge(doc.id);
        report.deleted++;
        continue;
      }
      await _pushDocument(doc, state, report);
    }
  }

  Future<void> _pushDocument(ScanDocument doc, SyncState state, SyncReport report, {int attempt = 0}) async {
    for (final p in doc.pages) {
      await _uploadPage(doc.id, p, state);
    }
    await _saveState(state);
    try {
      final server = await api.putDocument(doc.id, _toServer(doc, baseVersion: doc.serverVersion));
      await _markPushed(doc, server['version'] as int);
      report.pushed++;
    } on ConflictException catch (c) {
      report.conflicts++;
      final serverUpdated = DateTime.parse(c.server['updated_at'] as String);
      if (attempt == 0 && !doc.updatedAt.isBefore(serverUpdated)) {
        // Ours is newer: overwrite, based on the version we just saw.
        await _pushDocument(_withServerVersion(doc, c.server['version'] as int), state, report, attempt: 1);
      } else {
        await _applyServer(c.server, state, force: true);
        report.pulled++;
      }
    } on ApiException catch (e) {
      // The server lost files we thought it had: forget them and retry once.
      if (e.status == 422 && attempt == 0 && e.body.toString().contains('missing')) {
        for (final p in doc.pages) {
          state.pages.remove(p.id);
        }
        await _pushDocument(doc, state, report, attempt: 1);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _uploadPage(String docId, ScanPage p, SyncState state) async {
    final done = state.pages[p.id];
    final needSource = done == null || done.$2 != p.sourceVersion;
    final needRender = done == null || done.$1 != p.revision;
    if (!needSource && !needRender) return;
    for (final kind in [if (needSource) PageImage.source, if (needRender) PageImage.render, if (needRender) PageImage.thumb]) {
      final bytes = await repo.pageImage(p.id, kind);
      if (bytes == null) throw StateError('page ${p.id} is missing its ${kind.name} image');
      await api.putPageFile(docId, p.id, _kinds[kind]!, bytes);
    }
    state.pages[p.id] = (p.revision, p.sourceVersion);
  }

  /// Record success without clobbering edits made while the request was in flight.
  Future<void> _markPushed(ScanDocument pushed, int serverVersion) async {
    final latest = await repo.get(pushed.id) ?? pushed;
    await repo.save(latest.markSynced(remoteId: pushed.id, revision: pushed.revision, serverVersion: serverVersion));
  }

  ScanDocument _withServerVersion(ScanDocument d, int v) => ScanDocument.fromJson({...d.toJson(), 'serverVer': v});

  // ---------------- pull ----------------

  Future<void> _pull(SyncState state, SyncReport report) async {
    while (true) {
      final res = await api.listDocuments(since: state.cursor);
      for (final s in (res['documents'] as List).cast<Map<String, dynamic>>()) {
        if (await _applyServer(s, state)) report.pulled++;
      }
      state.cursor = res['cursor'] as int;
      await _saveState(state);
      if (res['has_more'] != true) break;
    }
  }

  /// Apply one server document. Returns whether the local library changed.
  /// Without [force], a local edit newer than the server copy is kept (and
  /// pushed next time against the new server version).
  Future<bool> _applyServer(Map<String, dynamic> s, SyncState state, {bool force = false}) async {
    final id = s['id'] as String;
    final version = s['version'] as int;
    final serverUpdated = DateTime.parse(s['updated_at'] as String).toLocal();
    final local = await repo.get(id);

    if (local != null && local.serverVersion == version && !force) return false; // our own push echoed back
    if (local != null && local.needsSync && !force) {
      if (local.updatedAt.isAfter(serverUpdated)) {
        // Local edit is newer: keep it, push it on top of this version.
        await repo.save(_withServerVersion(local, version));
        return false;
      }
    }

    if (s['deleted'] == true) {
      if (local == null) return false;
      for (final p in local.pages) {
        await repo.deletePageImages(p.id);
        state.pages.remove(p.id);
      }
      await repo.purge(id);
      return true;
    }

    final pages = <ScanPage>[];
    for (final sp in (s['pages'] as List).cast<Map<String, dynamic>>()) {
      final page = _pageFromServer(sp);
      final known = state.pages[page.id];
      final have = local?.pages.where((p) => p.id == page.id).firstOrNull;
      final needSource = known == null || known.$2 != page.sourceVersion || have == null;
      final needRender = known == null || known.$1 != page.revision || have == null;
      for (final kind in [if (needSource) PageImage.source, if (needRender) PageImage.render, if (needRender) PageImage.thumb]) {
        final bytes = await api.getPageFile(id, page.id, _kinds[kind]!);
        await repo.putPageImage(page.id, kind, Uint8List.fromList(bytes));
      }
      if (needSource || !_sameGeometry(have, page)) {
        // The flattened image is derived locally from source + corners; rebuilt on the next edit.
        await _dropFlat(page.id);
      }
      state.pages[page.id] = (page.revision, page.sourceVersion);
      pages.add(page);
    }
    for (final old in local?.pages ?? const <ScanPage>[]) {
      if (!pages.any((p) => p.id == old.id)) {
        await repo.deletePageImages(old.id);
        state.pages.remove(old.id);
      }
    }
    final rev = (local?.revision ?? 0) + 1;
    await repo.save(ScanDocument(
      id: id,
      title: s['title'] as String,
      createdAt: DateTime.parse(s['created_at'] as String).toLocal(),
      updatedAt: serverUpdated,
      pages: pages,
      revision: rev,
      remoteId: id,
      syncedRevision: rev,
      serverVersion: version,
    ));
    await _saveState(state);
    return true;
  }

  bool _sameGeometry(ScanPage a, ScanPage b) =>
      a.sourceVersion == b.sourceVersion && a.corners.toString() == b.corners.toString();

  Future<void> _dropFlat(String pageId) => store.delete(DocumentRepository.pageImageKey(pageId, PageImage.flat));

  // ---------------- mapping ----------------

  static Map<String, dynamic> _toServer(ScanDocument d, {int? baseVersion}) => {
        'title': d.title,
        'created_at': d.createdAt.toUtc().toIso8601String(),
        'updated_at': d.updatedAt.toUtc().toIso8601String(),
        'base_version': baseVersion,
        'pages': [
          for (final p in d.pages)
            {
              'id': p.id,
              'source_width': p.sourceWidth,
              'source_height': p.sourceHeight,
              'corners': [for (final c in p.corners) [c.x, c.y]],
              'edits': {
                'filter': p.edits.filter.wireName,
                'turns': p.edits.quarterTurns,
                'crop': p.edits.crop.toJson(),
              },
              'revision': p.revision,
              'source_version': p.sourceVersion,
              'render_width': p.renderWidth,
              'render_height': p.renderHeight,
              if (p.ocrText != null) 'ocr_text': p.ocrText,
            },
        ],
      };

  static ScanPage _pageFromServer(Map<String, dynamic> j) {
    final e = (j['edits'] as Map).cast<String, dynamic>();
    return ScanPage(
      id: j['id'] as String,
      sourceWidth: j['source_width'] as int,
      sourceHeight: j['source_height'] as int,
      corners: [for (final c in j['corners'] as List) Pt(((c as List)[0] as num).toDouble(), (c[1] as num).toDouble())],
      edits: PageEdits(
        filter: PageFilter.fromWire(e['filter'] as String?),
        quarterTurns: e['turns'] as int? ?? 0,
        crop: e['crop'] == null ? CropRect.full : CropRect.fromJson(e['crop'] as List),
      ),
      revision: j['revision'] as int? ?? 0,
      sourceVersion: j['source_version'] as int? ?? 0,
      renderWidth: j['render_width'] as int? ?? 0,
      renderHeight: j['render_height'] as int? ?? 0,
      ocrText: j['ocr_text'] as String?,
      // Text from the server is current for this revision (line boxes stay on the device that ran OCR).
      ocrRevision: j['ocr_text'] == null ? -1 : j['revision'] as int? ?? 0,
    );
  }
}
