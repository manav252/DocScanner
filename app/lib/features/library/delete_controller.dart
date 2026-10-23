// Deleting a document feels instant: the card disappears at once, a snackbar
// offers Undo for a few seconds, and only then are the files removed in the
// background. If that fails, the document comes back with an error message.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/models.dart';

/// Ids of documents the user deleted whose files are not removed yet
/// (hidden from every list meanwhile).
class PendingDeletes extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void hide(String id) => state = {...state, id};
  void show(String id) => state = {...state}..remove(id);
}

final pendingDeletesProvider = NotifierProvider<PendingDeletes, Set<String>>(PendingDeletes.new);

/// How long Undo is offered before the files are deleted.
const undoWindow = Duration(seconds: 5);

class DeleteController {
  DeleteController(this._ref);
  final Ref _ref;
  final _timers = <String, Timer>{};

  /// Hide [doc] now; delete its files after [undoWindow] unless [undo] is called.
  /// [onFailed] runs if the background delete fails (the document is shown again).
  void request(ScanDocument doc, {Duration delay = undoWindow, void Function(Object error)? onFailed}) {
    _ref.read(pendingDeletesProvider.notifier).hide(doc.id);
    _timers[doc.id]?.cancel();
    _timers[doc.id] = Timer(delay, () => commit(doc.id, onFailed: onFailed));
  }

  /// Bring the document back (Undo).
  void undo(String id) {
    _timers.remove(id)?.cancel();
    _ref.read(pendingDeletesProvider.notifier).show(id);
  }

  /// Delete the files now (also used when the snackbar closes early).
  Future<void> commit(String id, {void Function(Object error)? onFailed}) async {
    _timers.remove(id)?.cancel();
    if (!_ref.read(pendingDeletesProvider).contains(id)) return; // undone
    final repo = _ref.read(documentRepositoryProvider);
    try {
      final doc = await repo.get(id);
      if (doc != null) await repo.delete(doc);
      // The id stays hidden: the document is gone, and the card must not flash back
      // before the list has caught up.
    } catch (e) {
      _ref.read(pendingDeletesProvider.notifier).show(id);
      onFailed?.call(e);
    }
  }

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
  }
}

final deleteControllerProvider = Provider<DeleteController>((ref) {
  final c = DeleteController(ref);
  ref.onDispose(c.dispose);
  return c;
});

/// Delete [doc] with an Undo snackbar. Works from any screen: the snackbar is
/// shown by the app-wide messenger, so it survives leaving the editor.
void deleteWithUndo(BuildContext context, WidgetRef ref, ScanDocument doc) {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(deleteControllerProvider);
  controller.request(
    doc,
    onFailed: (_) => messenger
      ..hideCurrentSnackBar() // the Undo offer no longer applies
      ..showSnackBar(SnackBar(content: Text(l.deleteFailed(doc.title)))),
  );
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(l.documentDeleted),
      duration: undoWindow,
      persist: false,
      action: SnackBarAction(label: l.undo, onPressed: () => controller.undo(doc.id)),
    ),
  );
}
