// All documents: search (titles and recognised text), open, rename, export, delete.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/models.dart';
import '../capture/capture_page.dart';
import '../common/dialogs.dart';
import '../common/document_card.dart';
import '../editor/document_editor_page.dart';
import '../editor/export_sheet.dart';
import 'library_controller.dart';

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  late final _search = TextEditingController(text: ref.read(libraryQueryProvider));

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String q) => ref.read(libraryQueryProvider.notifier).set(q);

  Future<void> _rename(ScanDocument doc) async {
    final title = await showDialog<String>(context: context, builder: (_) => RenameDialog(initial: doc.title));
    if (title != null) await ref.read(libraryActionsProvider).rename(doc, title);
  }

  Future<void> _delete(ScanDocument doc) async {
    final l = context.l10n;
    if (await confirmDelete(context, l.deleteDocumentTitle(doc.title), l.deleteDocumentBody(doc.pages.length))) {
      await ref.read(libraryActionsProvider).delete(doc);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.documentDeleted)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final docs = ref.watch(libraryProvider);
    final query = ref.watch(libraryQueryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.documents)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                key: const ValueKey('library-search'),
                controller: _search,
                onChanged: _setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l.searchDocuments,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: TextButton.icon(
                            key: const ValueKey('clear-search'),
                            icon: const Icon(Icons.clear),
                            label: Text(l.clearSearch),
                            onPressed: () {
                              _search.clear();
                              _setQuery('');
                            },
                          ),
                        ),
                ),
              ),
            ),
            Expanded(
              child: switch (docs) {
                AsyncData(value: final list) when list.isEmpty => query.isEmpty
                    ? _Empty(
                        title: l.noScansYet,
                        body: l.noScansHint,
                        action: FilledButton.icon(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => const CapturePage())),
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: Text(l.scanDocument),
                        ),
                      )
                    : _Empty(
                        title: l.noResults(query),
                        action: OutlinedButton.icon(
                          onPressed: () {
                            _search.clear();
                            _setQuery('');
                          },
                          icon: const Icon(Icons.clear),
                          label: Text(l.clearSearch),
                        ),
                      ),
                AsyncData(value: final list) => ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => DocumentCard(
                      doc: list[i],
                      onOpen: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => DocumentEditorPage(documentId: list[i].id))),
                      onRename: () => _rename(list[i]),
                      onExport: () => showExportSheet(context, list[i]),
                      onDelete: () => _delete(list[i]),
                    ),
                  ),
                AsyncError(:final error) => _Empty(title: '$error'),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, this.body, this.action});
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_open_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (body != null) ...[const SizedBox(height: 8), Text(body!, textAlign: TextAlign.center)],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}
