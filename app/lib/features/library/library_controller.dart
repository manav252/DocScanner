// Library state: the document list (live-updating) and the search query.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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

  Future<void> delete(ScanDocument doc) async {
    final repo = _ref.read(documentRepositoryProvider);
    await repo.delete(await repo.get(doc.id) ?? doc);
  }
}

final libraryActionsProvider = Provider<LibraryActions>(LibraryActions.new);
