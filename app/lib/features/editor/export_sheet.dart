// Export a document as PDF or JPG(s): share (share sheet / Web Share) or download (web).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../data/models.dart';
import '../../services/export/pdf_builder.dart';
import 'export.dart';
import 'ocr_runner.dart';

Future<void> showExportSheet(BuildContext context, ScanDocument doc) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => ExportSheet(doc: doc),
);

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key, required this.doc});
  final ScanDocument doc;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  var _format = ExportFormat.pdf;
  var _size = PdfPageSize.fit;
  bool _busy = false;
  bool _searchable = true;
  String? _step;

  Future<void> _go({required bool download}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      var doc = widget.doc;
      final ocr = ref.read(ocrRunnerProvider);
      if (_format == ExportFormat.pdf && _searchable && ocr.available) {
        await ocr.run(
          doc.id,
          onProgress: (p) {
            if (mounted && p.total > 0) {
              setState(() => _step = l.recognizingTextOf(p.done + 1 > p.total ? p.total : p.done + 1, p.total));
            }
          },
        );
        doc = await ref.read(documentRepositoryProvider).get(doc.id) ?? doc;
      }
      if (mounted) setState(() => _step = _format == ExportFormat.pdf ? l.creatingPdf : l.creatingImages);
      final files = await ref.read(exporterProvider).build(doc, format: _format, pageSize: _size);
      final share = ref.read(shareServiceProvider);
      if (download) {
        await share.download(files);
      } else {
        await share.share(files, subject: widget.doc.title);
      }
      if (mounted) Navigator.of(context).pop();
      if (download) {
        messenger.showSnackBar(
          SnackBar(content: Text(files.length == 1 ? l.savedFile(files.first.name) : l.savedImages(files.length))),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.exportFailed(e is StateError ? e.message : '$e'))));
      if (mounted) {
        setState(() {
          _busy = false;
          _step = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canDownload = ref.watch(shareServiceProvider).canDownload;
    final n = widget.doc.pages.length;
    final hasMarkup = widget.doc.pages.any((p) => p.markup.isNotEmpty);
    final help = kIsWeb
        ? l.exportHelpWeb
        : defaultTargetPlatform == TargetPlatform.iOS
        ? l.exportHelpIos
        : l.exportHelpAndroid;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l.exportTitle(widget.doc.title), style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 16),
            SegmentedButton<ExportFormat>(
              segments: [
                ButtonSegment(
                  value: ExportFormat.pdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(l.formatPdf),
                ),
                ButtonSegment(value: ExportFormat.jpg, icon: const Icon(Icons.image), label: Text(l.formatJpg(n))),
              ],
              selected: {_format},
              onSelectionChanged: _busy ? null : (s) => setState(() => _format = s.first),
            ),
            if (_format == ExportFormat.pdf) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<PdfPageSize>(
                initialValue: _size,
                decoration: InputDecoration(labelText: l.pageSize, border: const OutlineInputBorder()),
                items: [
                  for (final s in PdfPageSize.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(switch (s) {
                        PdfPageSize.fit => l.pageSizeFit,
                        PdfPageSize.a4 => l.pageSizeA4,
                        PdfPageSize.letter => l.pageSizeLetter,
                      }),
                    ),
                ],
                onChanged: _busy ? null : (s) => setState(() => _size = s ?? _size),
              ),
              if (ref.read(ocrRunnerProvider).available)
                CheckboxListTile(
                  key: const ValueKey('searchable-pdf'),
                  contentPadding: EdgeInsets.zero,
                  value: _searchable,
                  onChanged: _busy ? null : (v) => setState(() => _searchable = v ?? true),
                  title: Text(l.searchablePdf),
                  subtitle: Text(l.searchablePdfHint),
                ),
            ],
            const SizedBox(height: 12),
            if (hasMarkup) Text(l.markupBurnedIn),
            Text(help, key: const ValueKey('export-help'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_busy && _step != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_step!)),
            if (_busy) const SizedBox(height: 12),
            Row(
              children: [
                if (canDownload)
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('export-download'),
                      onPressed: _busy ? null : () => _go(download: true),
                      icon: const Icon(Icons.download),
                      label: Text(l.download),
                    ),
                  ),
                if (canDownload) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('export-share'),
                    onPressed: _busy ? null : () => _go(download: false),
                    icon: const Icon(Icons.share),
                    label: Text(canDownload ? l.share : l.shareOrSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
