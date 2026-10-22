// Home: the local document library with search, plus Scan and Import.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../data/sync/sync_controller.dart';
import '../account/account_page.dart';
import '../capture/capture_page.dart';
import '../common/page_image.dart';
import '../diagnostics/detector_diagnostics_page.dart';
import '../editor/document_editor_page.dart';
import '../editor/export_sheet.dart';
import 'import_flow.dart';
import 'library_controller.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(ScanDocument doc) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => DocumentEditorPage(documentId: doc.id)));

  void _scan() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CapturePage()));

  Future<void> _import({required bool files}) async {
    final importer = ref.read(importServiceProvider);
    final picked = files ? await importer.pickFiles() : await importer.pickImages();
    if (picked.isEmpty || !mounted) return;
    final progress = ValueNotifier<ImportProgress>(const ImportProgress(0, 'Preparing…'));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Importing'),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (_, p, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text('${p.done} pages · ${p.label}', maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ),
    );
    final first = picked.first.name;
    final title = first.contains('.') ? first.substring(0, first.lastIndexOf('.')) : first;
    try {
      final doc = await ref.read(libraryActionsProvider).createDocument(title: picked.length == 1 ? title : null);
      final n = await ref.read(importFlowProvider).importFiles(doc.id, picked, onProgress: (p) => progress.value = p);
      if (!mounted) return;
      Navigator.of(context).pop(); // progress dialog
      if (n == 0) {
        await ref.read(libraryActionsProvider).delete(doc);
        _snack('Nothing to import.');
      } else {
        _open(doc);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack('Import failed: $e');
    } finally {
      progress.dispose();
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _rename(ScanDocument doc) async {
    final title = await showDialog<String>(context: context, builder: (_) => RenameDialog(initial: doc.title));
    if (title != null) await ref.read(libraryActionsProvider).rename(doc, title);
  }

  Future<void> _delete(ScanDocument doc) async {
    if (await confirmDelete(context, 'Delete "${doc.title}"?', 'All ${doc.pages.length} pages will be removed.')) {
      await ref.read(libraryActionsProvider).delete(doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(libraryProvider);
    final query = ref.watch(libraryQueryProvider);
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                key: const ValueKey('library-search'),
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search documents', border: InputBorder.none),
                onChanged: ref.read(libraryQueryProvider.notifier).set,
              )
            : const Text('DocScanner'),
        actions: [
          IconButton(
            key: const ValueKey('account'),
            tooltip: describeSync(ref.watch(syncControllerProvider)),
            icon: SyncIcon(status: ref.watch(syncControllerProvider)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPage())),
          ),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                ref.read(libraryQueryProvider.notifier).set('');
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (_) => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const DetectorDiagnosticsPage())),
            itemBuilder: (_) => const [PopupMenuItem(value: 'diag', child: Text('Detector diagnostics'))],
          ),
        ],
      ),
      body: switch (docs) {
        AsyncData(value: final list) when list.isEmpty => query.isEmpty
            ? _EmptyLibrary(onScan: _scan, onImport: () => _import(files: true))
            : Center(child: Text('No documents match "$query"')),
        AsyncData(value: final list) => GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 0.68,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => _DocumentCard(
              doc: list[i],
              onOpen: () => _open(list[i]),
              onRename: () => _rename(list[i]),
              onShare: () => showExportSheet(context, list[i]),
              onDelete: () => _delete(list[i]),
            ),
          ),
        AsyncError(:final error) => Center(child: Text('Could not load documents: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        PopupMenuButton<bool>(
          tooltip: 'Import',
          onSelected: (files) => _import(files: files),
          itemBuilder: (_) => const [
            PopupMenuItem(value: false, child: ListTile(leading: Icon(Icons.photo_library), title: Text('Photos'))),
            PopupMenuItem(value: true, child: ListTile(leading: Icon(Icons.upload_file), title: Text('PDF or image files'))),
          ],
          child: const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Chip(avatar: Icon(Icons.file_upload_outlined), label: Text('Import')),
          ),
        ),
        FloatingActionButton.extended(
          key: const ValueKey('scan-fab'),
          onPressed: _scan,
          icon: const Icon(Icons.document_scanner),
          label: const Text('Scan'),
        ),
      ]),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.doc,
    required this.onOpen,
    required this.onRename,
    required this.onShare,
    required this.onDelete,
  });
  final ScanDocument doc;
  final VoidCallback onOpen, onRename, onShare, onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = doc.updatedAt;
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Card(
      key: ValueKey('doc-${doc.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: doc.pages.isEmpty
                  ? const Icon(Icons.description_outlined, size: 48)
                  : Padding(padding: const EdgeInsets.all(8), child: StoredPageImage(page: doc.pages.first)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  Text('${doc.pages.length} ${doc.pages.length == 1 ? 'page' : 'pages'} · $date',
                      style: theme.textTheme.bodySmall),
                ]),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'rename' => onRename(),
                  'share' => onShare(),
                  _ => onDelete(),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  if (doc.pages.isNotEmpty) const PopupMenuItem(value: 'share', child: Text('Export / share')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onScan, required this.onImport});
  final VoidCallback onScan, onImport;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.document_scanner_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No scans yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Scan a document with your camera, or import photos and PDFs.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.photo_camera), label: const Text('Scan')),
              OutlinedButton.icon(onPressed: onImport, icon: const Icon(Icons.upload_file), label: const Text('Import')),
            ]),
          ]),
        ),
      );
}
