// Library state: the document list (live-updating) and the search query.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_settings.dart';
import '../../core/providers.dart';
import '../../data/models.dart';

class LibraryQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final libraryQueryProvider = NotifierProvider<LibraryQuery, String>(LibraryQuery.new);

/// Visible documents matching the query, newest first; refreshes on every change.
final libraryProvider = StreamProvider.autoDispose<List<ScanDocument>>((ref) async* {
  final repo = ref.watch(documentRepositoryProvider);
  final query = ref.watch(libraryQueryProvider);
  yield await repo.list(query: query);
  await for (final _ in repo.changes) {
    yield await repo.list(query: query);
  }
});

/// Library-level operations (not tied to an open editor).
class LibraryActions {
  const LibraryActions(this._ref);
  final Ref _ref;

  Future<ScanDocument> createDocument({String? title}) async {
    final now = DateTime.now();
    final doc = ScanDocument(
      id: const Uuid().v4(),
      title: title ?? ScanDocument.defaultTitle(now),
      createdAt: now,
      updatedAt: now,
      // Signed in: new scans are backed up. Guest: they stay on this device.
      backup: _ref.read(sessionProvider) != null,
    );
    await _ref.read(documentRepositoryProvider).save(doc);
    return doc;
  }

  Future<void> rename(ScanDocument doc, String title) async {
    final t = title.trim();
    if (t.isEmpty || t == doc.title) return;
    final repo = _ref.read(documentRepositoryProvider);
    final latest = await repo.get(doc.id) ?? doc;
    await repo.save(latest.edit(title: t));
  }

  /// Documents on this device that are not backed up (offered for upload after sign-in).
  Future<List<ScanDocument>> localOnly() async => [
    for (final d in await _ref.read(documentRepositoryProvider).list())
      if (!d.backup) d,
  ];

  /// Opt documents into backup; sync uploads them.
  Future<void> backUp(Iterable<ScanDocument> docs) async {
    final repo = _ref.read(documentRepositoryProvider);
    for (final d in docs) {
      final latest = await repo.get(d.id) ?? d;
      if (!latest.backup) await repo.save(latest.edit(backup: true, now: latest.updatedAt));
    }
  }

  Future<void> delete(ScanDocument doc) async {
    final repo = _ref.read(documentRepositoryProvider);
    await repo.delete(await repo.get(doc.id) ?? doc);
  }
}

final libraryActionsProvider = Provider<LibraryActions>(LibraryActions.new);

/// How many documents are on this device only / waiting to upload / backed up.
typedef BackupSummary = ({int localOnly, int pending, int backedUp});

final backupSummaryProvider = StreamProvider.autoDispose<BackupSummary>((ref) async* {
  final repo = ref.watch(documentRepositoryProvider);
  Future<BackupSummary> count() async {
    var local = 0, pending = 0, ok = 0;
    for (final d in await repo.list()) {
      if (!d.backup) {
        local++;
      } else if (d.needsSync) {
        pending++;
      } else {
        ok++;
      }
    }
    return (localOnly: local, pending: pending, backedUp: ok);
  }

  yield await count();
  await for (final _ in repo.changes) {
    yield await count();
  }
});
