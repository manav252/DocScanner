// Review/edit a scanned document: page viewer, reorderable page strip and
// per-page tools (filters, rotate, crop, corners, retake, delete).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/page_edits.dart';
import '../capture/capture_page.dart';
import '../common/dialogs.dart';
import '../common/page_image.dart';
import '../corners/corner_adjust_page.dart';
import '../library/import_flow.dart';
import '../library/library_controller.dart';
import 'crop_page.dart';
import 'document_controller.dart';
import 'export_sheet.dart';
import 'filter_sheet.dart';
import 'ocr_runner.dart';
import 'text_sheet.dart';

class DocumentEditorPage extends ConsumerStatefulWidget {
  const DocumentEditorPage({super.key, required this.documentId});
  final String documentId;

  @override
  ConsumerState<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends ConsumerState<DocumentEditorPage> {
  final _pager = PageController();
  int _current = 0;
  int _busy = 0;

  /// Background text recognition progress (null when idle).
  OcrProgress? _ocr;

  /// Recognise text for new/changed pages in the background (if enabled).
  void _maybeOcr(ScanDocument doc) {
    if (_ocr != null || _busy > 0 || !doc.pages.any((p) => p.needsOcr)) return;
    if (!ref.read(appSettingsProvider).autoOcr || !ref.read(ocrRunnerProvider).available) return;
    setState(() => _ocr = const OcrProgress(0, 0));
    ref
        .read(ocrRunnerProvider)
        .run(widget.documentId, onProgress: (p) => mounted ? setState(() => _ocr = p) : null)
        .catchError((Object _) => 0) // OCR is best-effort; the Text tool shows errors
        .whenComplete(() {
      if (!mounted) return;
      setState(() => _ocr = null);
      final latest = ref.read(documentProvider(widget.documentId)).value;
      if (latest != null && latest.pages.any((p) => p.needsOcr)) {
        // Pages changed while recognising: catch up shortly.
        Future<void>.delayed(const Duration(seconds: 1), () => mounted ? _maybeOcr(latest) : null);
      }
    });
  }

  DocumentController get _doc => ref.read(documentProvider(widget.documentId).notifier);

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// Run an edit with a progress bar and error reporting.
  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy++);
    try {
      await op();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
    } finally {
      if (mounted) setState(() => _busy--);
    }
  }

  void _goTo(int i) {
    setState(() => _current = i);
    if (_pager.hasClients) _pager.jumpToPage(i);
  }

  Future<void> _rename(ScanDocument doc) async {
    final title = await showDialog<String>(context: context, builder: (_) => RenameDialog(initial: doc.title));
    if (title != null) await _run(() => _doc.rename(title));
  }

  Future<void> _deleteDocument(ScanDocument doc) async {
    final ok = await confirmDelete(context, 'Delete "${doc.title}"?', 'All ${doc.pages.length} pages will be removed.');
    if (!ok || !mounted) return;
    await ref.read(libraryActionsProvider).delete(doc);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _scanMore() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CapturePage(documentId: widget.documentId)));
  }

  Future<void> _import({required bool files}) async {
    final importer = ref.read(importServiceProvider);
    final picked = files ? await importer.pickFiles() : await importer.pickImages();
    if (picked.isEmpty || !mounted) return;
    await _run(() => ref.read(importFlowProvider).importFiles(widget.documentId, picked));
  }

  Future<void> _adjustCorners(ScanPage page) async {
    final source = await ref.read(documentRepositoryProvider).pageImage(page.id, PageImage.source);
    if (source == null || !mounted) return;
    final result = await Navigator.of(context).push<CornerAdjustResult>(MaterialPageRoute(
      builder: (_) => CornerAdjustPage(
        bytes: source,
        width: page.sourceWidth,
        height: page.sourceHeight,
        corners: page.corners,
      ),
    ));
    if (result == null) return;
    await _run(() => result.rotated
        ? _doc.replaceImage(page.id, result.bytes, result.width, result.height, result.corners)
        : _doc.setCorners(page.id, result.corners));
  }

  Future<void> _crop(ScanPage page) async {
    final crop = await Navigator.of(context).push(MaterialPageRoute<CropRect>(
      builder: (_) => CropPage(page: page),
    ));
    if (crop != null) await _run(() => _doc.setCrop(page.id, crop));
  }

  Future<void> _deletePage(ScanDocument doc, ScanPage page) async {
    if (doc.pages.length == 1) {
      await _deleteDocument(doc);
      return;
    }
    final ok = await confirmDelete(context, 'Delete this page?', 'Page ${doc.pages.indexOf(page) + 1} will be removed.');
    if (!ok) return;
    await _run(() => _doc.deletePage(page.id));
    if (_current >= doc.pages.length - 1) _goTo((doc.pages.length - 2).clamp(0, 1 << 20));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentProvider(widget.documentId));
    return switch (async) {
      AsyncError(:final error) => Scaffold(appBar: AppBar(), body: Center(child: Text('$error'))),
      AsyncData(value: final doc) => _build(doc),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }

  Widget _build(ScanDocument doc) {
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _maybeOcr(doc) : null);
    final pages = doc.pages;
    final current = pages.isEmpty ? null : pages[_current.clamp(0, pages.length - 1)];
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => _rename(doc),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(doc.title, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            const Icon(Icons.edit, size: 18),
          ]),
        ),
        actions: [
          IconButton(
            key: const ValueKey('export'),
            tooltip: 'Export / share',
            icon: const Icon(Icons.ios_share),
            onPressed: pages.isEmpty || _busy > 0 ? null : () => showExportSheet(context, doc),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'delete' ? _deleteDocument(doc) : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete document'))],
          ),
        ],
        bottom: _busy > 0
            ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
            : _ocr != null
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(22),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _ocr!.total == 0 ? 'Recognizing text…' : 'Recognizing text ${_ocr!.done + 1} of ${_ocr!.total}…',
                        key: const ValueKey('ocr-progress'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  )
                : null,
      ),
      body: pages.isEmpty
          ? _EmptyDocument(onScan: _scanMore, onImport: () => _import(files: true))
          : Column(children: [
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Material(
                        elevation: 3,
                        child: StoredPageImage(key: ValueKey('page-view-$i'), page: pages[i], kind: PageImage.render),
                      ),
                    ),
                  ),
                ),
              ),
              Text('Page ${_current + 1} of ${pages.length}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 104,
                child: _PageStrip(
                  pages: pages,
                  current: _current,
                  onTap: _goTo,
                  onReorder: (from, to) {
                    final moved = pages[from].id;
                    _run(() async {
                      await _doc.reorder(from, to);
                      final i = ref.read(documentProvider(widget.documentId)).value?.pages.indexWhere((p) => p.id == moved);
                      if (i != null && i >= 0) _goTo(i);
                    });
                  },
                  onAdd: (choice) => switch (choice) {
                    _AddChoice.camera => _scanMore(),
                    _AddChoice.photos => _import(files: false),
                    _AddChoice.files => _import(files: true),
                  },
                ),
              ),
              const Divider(height: 1),
              _Toolbar(
                enabled: _busy == 0 && current != null,
                onFilters: () => showFilterSheet(
                  context,
                  page: current!,
                  onSelected: (f) => _run(() => _doc.setFilter(current.id, f)),
                  onApplyAll: (f) => _run(() => _doc.applyFilterToAll(f)),
                ),
                onRotate: () => _run(() => _doc.rotate(current!.id)),
                onText: () => showTextSheet(context, documentId: widget.documentId, pageId: current!.id),
                onCrop: () => _crop(current!),
                onCorners: () => _adjustCorners(current!),
                onRetake: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CapturePage(documentId: widget.documentId, replacePageId: current!.id),
                )),
                onDelete: () => _deletePage(doc, current!),
              ),
            ]),
    );
  }
}

enum _AddChoice { camera, photos, files }

class _PageStrip extends StatelessWidget {
  const _PageStrip({
    required this.pages,
    required this.current,
    required this.onTap,
    required this.onReorder,
    required this.onAdd,
  });
  final List<ScanPage> pages;
  final int current;
  final ValueChanged<int> onTap;
  final void Function(int from, int to) onReorder;
  final ValueChanged<_AddChoice> onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: pages.length,
      onReorderItem: onReorder,
      buildDefaultDragHandles: false,
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: PopupMenuButton<_AddChoice>(
          tooltip: 'Add pages',
          onSelected: onAdd,
          itemBuilder: (_) => const [
            PopupMenuItem(value: _AddChoice.camera, child: ListTile(leading: Icon(Icons.photo_camera), title: Text('Scan more'))),
            PopupMenuItem(value: _AddChoice.photos, child: ListTile(leading: Icon(Icons.photo_library), title: Text('Import photos'))),
            PopupMenuItem(
                value: _AddChoice.files, child: ListTile(leading: Icon(Icons.upload_file), title: Text('Import PDF or files'))),
          ],
          child: Container(
            width: 64,
            decoration: BoxDecoration(border: Border.all(color: scheme.outline), borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.add),
          ),
        ),
      ),
      itemBuilder: (_, i) => ReorderableDelayedDragStartListener(
        key: ValueKey(pages[i].id),
        index: i,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            label: 'Page ${i + 1}, long press and drag to reorder',
            child: GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: i == current ? scheme.primary : scheme.outlineVariant, width: i == current ? 3 : 1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(fit: StackFit.expand, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: StoredPageImage(page: pages[i])),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.enabled,
    required this.onFilters,
    required this.onRotate,
    required this.onCrop,
    required this.onCorners,
    required this.onRetake,
    required this.onDelete,
    required this.onText,
  });
  final bool enabled;
  final VoidCallback onFilters, onRotate, onCrop, onCorners, onRetake, onDelete, onText;

  @override
  Widget build(BuildContext context) {
    Widget tool(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon),
                  const SizedBox(height: 4),
                  Text(label, style: Theme.of(context).textTheme.labelSmall, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ),
        );
    return SafeArea(
      top: false,
      child: Row(children: [
        tool(Icons.auto_fix_high, 'Filters', onFilters),
        tool(Icons.rotate_right, 'Rotate', onRotate),
        tool(Icons.crop, 'Crop', onCrop),
        tool(Icons.crop_rotate, 'Corners', onCorners),
        tool(Icons.text_snippet_outlined, 'Text', onText),
        tool(Icons.replay, 'Retake', onRetake),
        tool(Icons.delete_outline, 'Delete', onDelete),
      ]),
    );
  }
}

class _EmptyDocument extends StatelessWidget {
  const _EmptyDocument({required this.onScan, required this.onImport});
  final VoidCallback onScan, onImport;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.description_outlined, size: 56),
          const SizedBox(height: 12),
          const Text('No pages yet'),
          const SizedBox(height: 16),
          Wrap(spacing: 12, children: [
            FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.photo_camera), label: const Text('Scan')),
            OutlinedButton.icon(onPressed: onImport, icon: const Icon(Icons.upload_file), label: const Text('Import')),
          ]),
        ]),
      );
}
