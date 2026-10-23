// Review/edit a scanned document: page viewer, reorderable page strip and
// per-page tools (filters, rotate, crop, corners, retake, delete).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/page_edits.dart';
import '../capture/capture_page.dart';
import '../common/dialogs.dart';
import '../common/page_image.dart';
import '../corners/corner_adjust_page.dart';
import '../markup/markup_editor_page.dart';
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
    final settings = ref.read(appSettingsProvider);
    final lang = settings.ocrLanguage.code;
    if (_ocr != null || _busy > 0 || !doc.pages.any((p) => p.needsOcrIn(lang))) return;
    if (!settings.autoOcr || !ref.read(ocrRunnerProvider).available) return;
    setState(() => _ocr = const OcrProgress(0, 0));
    ref
        .read(ocrRunnerProvider)
        .run(widget.documentId, onProgress: (p) => mounted ? setState(() => _ocr = p) : null)
        .catchError((Object _) => 0) // OCR is best-effort; the Text tool shows errors
        .whenComplete(() {
          if (!mounted) return;
          setState(() => _ocr = null);
          final latest = ref.read(documentProvider(widget.documentId)).value;
          if (latest != null && latest.pages.any((p) => p.needsOcrIn(lang))) {
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.somethingWentWrong(e is StateError ? e.message : '$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy--);
    }
  }

  void _goTo(int i) {
    setState(() => _current = i);
    if (_pager.hasClients) _pager.jumpToPage(i);
  }

  Future<void> _rename(ScanDocument doc) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => RenameDialog(initial: doc.title),
    );
    if (title != null) await _run(() => _doc.rename(title));
  }

  Future<void> _deleteDocument(ScanDocument doc) async {
    final l = context.l10n;
    final ok = await confirmDelete(context, l.deleteDocTitle(doc.title), l.deleteDocBody(doc.pages.length));
    if (!ok || !mounted) return;
    await ref.read(libraryActionsProvider).delete(doc);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _scanMore() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => CapturePage(documentId: widget.documentId)));
  }

  Future<void> _import({required bool files}) async {
    final importer = ref.read(importServiceProvider);
    final picked = files ? await importer.pickFiles() : await importer.pickImages();
    if (picked.isEmpty || !mounted) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await _run(() async {
      final r = await ref.read(importFlowProvider).importFiles(widget.documentId, picked);
      if (r.failed.isNotEmpty) messenger.showSnackBar(SnackBar(content: Text(l.importSkipped(r.failed.join(', ')))));
    });
  }

  Future<void> _adjustCorners(ScanPage page) async {
    final source = await ref.read(documentRepositoryProvider).pageImage(page.id, PageImage.source);
    if (source == null || !mounted) return;
    final result = await Navigator.of(context).push<CornerAdjustResult>(
      MaterialPageRoute(
        builder: (_) =>
            CornerAdjustPage(bytes: source, width: page.sourceWidth, height: page.sourceHeight, corners: page.corners),
      ),
    );
    if (result == null) return;
    await _run(
      () => result.rotated
          ? _doc.replaceImage(page.id, result.bytes, result.width, result.height, result.corners)
          : _doc.setCorners(page.id, result.corners),
    );
  }

  Future<void> _crop(ScanPage page) async {
    final crop = await Navigator.of(context).push(MaterialPageRoute<CropRect>(builder: (_) => CropPage(page: page)));
    if (crop != null) await _run(() => _doc.setCrop(page.id, crop));
  }

  /// Delete at once, with Undo in the snackbar (no confirmation dialog).
  Future<void> _deletePage(ScanDocument doc, ScanPage page) async {
    if (doc.pages.length == 1) {
      await _deleteDocument(doc);
      return;
    }
    final l = context.l10n;
    final number = doc.pages.indexOf(page) + 1;
    final messenger = ScaffoldMessenger.of(context);
    RemovedPage? removed;
    await _run(() async => removed = await _doc.removePage(page.id));
    if (_current >= doc.pages.length - 1) _goTo((doc.pages.length - 2).clamp(0, 1 << 20));
    final r = removed;
    if (r == null || !mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.pageDeleted(number)),
        duration: const Duration(seconds: 8),
        persist: false,
        action: SnackBarAction(
          label: l.undo,
          onPressed: () => _run(() async {
            await _doc.restorePage(r);
            _goTo(r.index);
          }),
        ),
      ),
    );
  }

  /// Move the current page one place (keyboard/screen-reader friendly reorder).
  Future<void> _move(ScanDocument doc, int from, int delta) async {
    final to = from + delta;
    if (to < 0 || to >= doc.pages.length) return;
    final l = context.l10n;
    await _run(() => _doc.reorder(from, to));
    _goTo(to);
    if (mounted) SemanticsService.sendAnnouncement(View.of(context), l.pageMoved(to + 1), Directionality.of(context));
  }

  Future<void> _addPages() async {
    final l = context.l10n;
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(l.addPages, style: Theme.of(c).textTheme.titleLarge),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l.scanMore),
              onTap: () => Navigator.pop(c, _AddChoice.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l.importPhotos),
              onTap: () => Navigator.pop(c, _AddChoice.photos),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: Text(l.importPdfOrFiles),
              onTap: () => Navigator.pop(c, _AddChoice.files),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case _AddChoice.camera:
        await _scanMore();
      case _AddChoice.photos:
        await _import(files: false);
      case _AddChoice.files:
        await _import(files: true);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentProvider(widget.documentId));
    return switch (async) {
      AsyncError() => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(context.l10n.documentNotFound)),
      ),
      AsyncData(value: final doc) => _build(doc),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }

  Widget _build(ScanDocument doc) {
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _maybeOcr(doc) : null);
    final l = context.l10n;
    final pages = doc.pages;
    final index = pages.isEmpty ? 0 : _current.clamp(0, pages.length - 1);
    final current = pages.isEmpty ? null : pages[index];
    final idle = _busy == 0 && current != null;
    final ocr = _ocr;
    // Phones / large text: Rename moves from the app bar into the toolbar.
    final narrow = MediaQuery.sizeOf(context).width < 600 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (!narrow)
            TextButton.icon(
              key: const ValueKey('rename-doc'),
              onPressed: () => _rename(doc),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.rename),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              key: const ValueKey('export'),
              onPressed: pages.isEmpty || _busy > 0 ? null : () => showExportSheet(context, doc),
              icon: const Icon(Icons.ios_share),
              label: Text(l.export),
            ),
          ),
        ],
        bottom: _busy > 0
            ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
            : ocr != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    ocr.total == 0 ? l.recognizingText : l.recognizingTextOf(ocr.done + 1, ocr.total),
                    key: const ValueKey('ocr-progress'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            : null,
      ),
      body: pages.isEmpty
          ? _EmptyDocument(onScan: _scanMore, onImport: () => _import(files: true))
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pager,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _current = i),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Semantics(
                          image: true,
                          label: l.pageOf(i + 1, pages.length),
                          child: Material(
                            elevation: 3,
                            child: StoredPageImage(
                              key: ValueKey('page-view-$i'),
                              page: pages[i],
                              kind: PageImage.render,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('prev-page'),
                      onPressed: index > 0 ? () => _goTo(index - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                      label: Text(l.previousPage),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l.pageOf(index + 1, pages.length), style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    TextButton.icon(
                      key: const ValueKey('next-page'),
                      onPressed: index < pages.length - 1 ? () => _goTo(index + 1) : null,
                      icon: const Icon(Icons.chevron_right),
                      iconAlignment: IconAlignment.end,
                      label: Text(l.nextPage),
                    ),
                  ],
                ),
                SizedBox(
                  // Grows with the text size so "Add pages" stays readable.
                  height: 80 + MediaQuery.textScalerOf(context).scale(32),
                  child: _PageStrip(
                    pages: pages,
                    current: index,
                    onTap: _goTo,
                    onReorder: (from, to) {
                      final moved = pages[from].id;
                      _run(() async {
                        await _doc.reorder(from, to);
                        final i = ref
                            .read(documentProvider(widget.documentId))
                            .value
                            ?.pages
                            .indexWhere((p) => p.id == moved);
                        if (i != null && i >= 0) _goTo(i);
                      });
                    },
                    onAdd: _busy > 0 ? null : _addPages,
                  ),
                ),
                const Divider(height: 1),
                _Toolbar(
                  tools: [
                    _Tool(
                      'tool-filters',
                      Icons.auto_fix_high,
                      l.toolFilters,
                      () => showFilterSheet(
                        context,
                        page: current!,
                        onSelected: (f) => _run(() => _doc.setFilter(current.id, f)),
                        onApplyAll: (f) => _run(() => _doc.applyFilterToAll(f)),
                      ),
                    ),
                    _Tool('tool-rotate', Icons.rotate_right, l.toolRotate, () => _run(() => _doc.rotate(current!.id))),
                    _Tool('tool-crop', Icons.crop, l.toolCrop, () => _crop(current!)),
                    _Tool('tool-corners', Icons.crop_rotate, l.toolCorners, () => _adjustCorners(current!)),
                    _Tool(
                      'tool-markup',
                      Icons.draw_outlined,
                      l.markup,
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MarkupEditorPage(documentId: widget.documentId, pageId: current!.id),
                        ),
                      ),
                    ),
                    _Tool(
                      'tool-text',
                      Icons.text_snippet_outlined,
                      l.toolPageText,
                      () => showTextSheet(context, documentId: widget.documentId, pageId: current!.id),
                    ),
                    _Tool(
                      'tool-retake',
                      Icons.replay,
                      l.toolRetake,
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CapturePage(documentId: widget.documentId, replacePageId: current!.id),
                        ),
                      ),
                    ),
                    if (pages.length > 1) ...[
                      _Tool(
                        'move-earlier',
                        Icons.arrow_back,
                        l.moveEarlier,
                        index > 0 ? () => _move(doc, index, -1) : null,
                      ),
                      _Tool(
                        'move-later',
                        Icons.arrow_forward,
                        l.moveLater,
                        index < pages.length - 1 ? () => _move(doc, index, 1) : null,
                      ),
                    ],
                    if (narrow) _Tool('rename-doc', Icons.edit_outlined, l.rename, () => _rename(doc)),
                    _Tool('delete-page', Icons.delete_outline, l.deletePage, () => _deletePage(doc, current!)),
                    _Tool('delete-doc', Icons.delete_forever_outlined, l.deleteDocument, () => _deleteDocument(doc)),
                  ],
                  enabled: idle,
                ),
              ],
            ),
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
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: pages.length,
      onReorderItem: onReorder,
      buildDefaultDragHandles: false,
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: 96,
          child: OutlinedButton(
            key: const ValueKey('add-pages'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: onAdd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add),
                Text(l.addPages, textAlign: TextAlign.center, maxLines: 2),
              ],
            ),
          ),
        ),
      ),
      itemBuilder: (_, i) => ReorderableDelayedDragStartListener(
        key: ValueKey(pages[i].id),
        index: i,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            button: true,
            selected: i == current,
            label: l.pageThumbLabel(i + 1),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 68,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: i == current ? scheme.primary : scheme.outline,
                    width: i == current ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: StoredPageImage(page: pages[i]),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: i == current ? scheme.primary : Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tool {
  const _Tool(this.key, this.icon, this.label, this.onTap);
  final String key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

/// Page tools: icon + text label each, scrolls sideways on narrow screens.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.tools, required this.enabled});
  final List<_Tool> tools;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Room for an icon and two lines of label at the user's text size.
    final scaled = MediaQuery.textScalerOf(context).scale(14);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 44 + scaled * 2 * 1.45,
        child: Scrollbar(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              for (final t in tools)
                SizedBox(
                  width: (92 * scaled / 14).clamp(92, 180),
                  child: TextButton(
                    key: ValueKey(t.key),
                    onPressed: enabled ? t.onTap : null,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      foregroundColor: t.key.startsWith('delete') ? theme.colorScheme.error : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon),
                        const SizedBox(height: 4),
                        Text(t.label, textAlign: TextAlign.center, maxLines: 2, style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDocument extends StatelessWidget {
  const _EmptyDocument({required this.onScan, required this.onImport});
  final VoidCallback onScan, onImport;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 56),
            const SizedBox(height: 12),
            Text(l.noPagesYet, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l.noPagesHint, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.photo_camera), label: Text(l.scanDocument)),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file),
                  label: Text(l.importPdfOrFiles),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
