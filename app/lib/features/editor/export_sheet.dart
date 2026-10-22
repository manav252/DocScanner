// Export a document as PDF or JPG(s): share (share sheet / Web Share) or download (web).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    try {
      var doc = widget.doc;
      final ocr = ref.read(ocrRunnerProvider);
      if (_format == ExportFormat.pdf && _searchable && ocr.available) {
        await ocr.run(doc.id, onProgress: (p) {
          if (mounted && p.total > 0) setState(() => _step = 'Recognizing text ${p.done + 1 > p.total ? p.total : p.done + 1} of ${p.total}…');
        });
        doc = await ref.read(documentRepositoryProvider).get(doc.id) ?? doc;
      }
      if (mounted) setState(() => _step = 'Creating ${_format == ExportFormat.pdf ? 'PDF' : 'images'}…');
      final files = await ref.read(exporterProvider).build(doc, format: _format, pageSize: _size);
      final share = ref.read(shareServiceProvider);
      if (download) {
        await share.download(files);
      } else {
        await share.share(files, subject: widget.doc.title);
      }
      if (mounted) Navigator.of(context).pop();
      if (download) {
        messenger.showSnackBar(SnackBar(content: Text('Saved ${files.length == 1 ? files.first.name : '${files.length} images'}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
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
    final canDownload = ref.watch(shareServiceProvider).canDownload;
    final n = widget.doc.pages.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Export "${widget.doc.title}"', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SegmentedButton<ExportFormat>(
            segments: [
              const ButtonSegment(value: ExportFormat.pdf, icon: Icon(Icons.picture_as_pdf), label: Text('PDF')),
              ButtonSegment(value: ExportFormat.jpg, icon: const Icon(Icons.image), label: Text(n == 1 ? 'JPG' : 'JPG ($n files)')),
            ],
            selected: {_format},
            onSelectionChanged: _busy ? null : (s) => setState(() => _format = s.first),
          ),
          if (_format == ExportFormat.pdf) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<PdfPageSize>(
              initialValue: _size,
              decoration: const InputDecoration(labelText: 'Page size', border: OutlineInputBorder()),
              items: [for (final s in PdfPageSize.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: _busy ? null : (s) => setState(() => _size = s ?? _size),
            ),
            if (ref.read(ocrRunnerProvider).available)
              CheckboxListTile(
                key: const ValueKey('searchable-pdf'),
                contentPadding: EdgeInsets.zero,
                value: _searchable,
                onChanged: _busy ? null : (v) => setState(() => _searchable = v ?? true),
                title: const Text('Searchable PDF'),
                subtitle: const Text('Recognize text so it can be searched and copied'),
              ),
          ],
          const SizedBox(height: 20),
          if (_busy) const LinearProgressIndicator(),
          if (_busy && _step != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_step!)),
          if (_busy) const SizedBox(height: 12),
          Row(children: [
            if (canDownload)
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('export-download'),
                  onPressed: _busy ? null : () => _go(download: true),
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ),
            if (canDownload) const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('export-share'),
                onPressed: _busy ? null : () => _go(download: false),
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
