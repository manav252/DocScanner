// Import photos or PDFs into a new document, with a progress dialog.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../services/import/import_service.dart';
import '../editor/document_editor_page.dart';
import 'import_flow.dart';
import 'library_controller.dart';

enum ImportKind { photos, pdf }

/// Pick files, import them into a new document and open it.
Future<void> importIntoNewDocument(BuildContext context, WidgetRef ref, ImportKind kind) async {
  final importer = ref.read(importServiceProvider);
  final List<ImportedFile> picked;
  try {
    picked = kind == ImportKind.photos ? await importer.pickImages() : await importer.pickPdfs();
  } catch (e) {
    if (context.mounted) _snack(context, context.l10n.importFailed('$e'));
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final l = context.l10n;
  final progress = ValueNotifier<ImportProgress>(const ImportProgress(0, ''));
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l.importing),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (_, p, _) => Semantics(
            liveRegion: true,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(l.importProgress(p.done, p.label), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ),
    ),
  );
  final first = picked.first.name;
  final title = first.contains('.') ? first.substring(0, first.lastIndexOf('.')) : first;
  final actions = ref.read(libraryActionsProvider);
  try {
    final doc = await actions.createDocument(title: picked.length == 1 ? title : null);
    final n = await ref.read(importFlowProvider).importFiles(doc.id, picked, onProgress: (p) => progress.value = p);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // progress dialog
    if (n == 0) {
      await actions.delete(doc);
      if (context.mounted) _snack(context, l.importNothing);
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocumentEditorPage(documentId: doc.id)));
    }
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    _snack(context, l.importFailed('$e'));
  } finally {
    progress.dispose();
  }
}

void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
