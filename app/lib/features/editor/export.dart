// Build export files (PDF or JPGs) from a document's rendered pages.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cancel.dart';
import '../../core/providers.dart';
import '../../data/document_repository.dart';
import '../../data/models.dart';
import '../../services/export/pdf_builder.dart';
import '../../services/export/share_service.dart';
import '../../imaging/markup.dart';
import '../../services/ocr/ocr_result.dart';
import '../markup/markup_painter.dart';

enum ExportFormat { pdf, jpg }

ByteData? _deva;

/// Bundled Noto Sans Devanagari (OFL) so Hindi text is searchable in PDFs.
Future<ByteData?> _devanagariFontBytes() async {
  try {
    return _deva ??= await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
  } catch (_) {
    return null; // without it, Hindi text is simply left out of the text layer
  }
}

typedef _PdfJob = ({List<PdfPageInput> pages, String title, PdfPageSize size, ByteData? font});

Future<Uint8List> _pdfJob(_PdfJob j) => buildPdf(
  j.pages,
  title: j.title,
  size: j.size,
  devanagariFont: j.font == null ? null : pw.Font.ttf(j.font!),
);

Future<List<OcrLine>?> _ocrLines(DocumentRepository repo, String pageId) async {
  final b = await repo.pageOcr(pageId);
  if (b == null) return null;
  try {
    return OcrResult.fromJson(jsonDecode(utf8.decode(b)) as Map<String, dynamic>).lines;
  } on FormatException {
    return null;
  }
}

class Exporter {
  const Exporter(this._ref);
  final Ref _ref;

  Future<List<ExportFile>> build(
    ScanDocument doc, {
    required ExportFormat format,
    PdfPageSize pageSize = PdfPageSize.fit,
    CancelToken? cancel,
    void Function(int done, int total)? onPage,
  }) {
    final engine = _ref.read(scanEngineProvider);
    return buildExport(
      _ref.read(documentRepositoryProvider),
      doc,
      format: format,
      pageSize: pageSize,
      cancel: cancel,
      onPage: onPage,
      // Markup is burned in, then re-encoded as JPEG (full size).
      flatten: (jpeg, items) async =>
          (await engine.normalizeEncoded(await flattenMarkup(jpeg, items), maxSide: 100000, quality: 92)).bytes,
    );
  }
}

final exporterProvider = Provider<Exporter>(Exporter.new);

Future<List<ExportFile>> buildExport(
  DocumentRepository repo,
  ScanDocument doc, {
  required ExportFormat format,
  PdfPageSize pageSize = PdfPageSize.fit,
  Future<Uint8List> Function(Uint8List jpeg, List<MarkupItem> items)? flatten,
  CancelToken? cancel,
  void Function(int done, int total)? onPage,
}) async {
  final name = safeFileName(doc.title);
  final images = <(ScanPage, Uint8List)>[];
  for (final (i, p) in doc.pages.indexed) {
    cancel?.check();
    onPage?.call(i, doc.pages.length);
    var bytes = await repo.pageImage(p.id, PageImage.render);
    if (bytes == null) continue;
    // Editable markup becomes part of the exported image.
    if (p.markup.isNotEmpty && flatten != null) bytes = await flatten(bytes, p.markup);
    images.add((p, bytes));
  }
  if (images.isEmpty) throw StateError('This document has no pages');
  cancel?.check();
  onPage?.call(doc.pages.length, doc.pages.length);
  return switch (format) {
    ExportFormat.pdf => [
      ExportFile(
        '$name.pdf',
        // Phones: built in a background isolate so the UI keeps moving. (On the
        // web `compute` runs inline; the page JPEGs are embedded as-is, not re-encoded.)
        await compute(_pdfJob, (
          pages: [
            for (final (p, b) in images)
              PdfPageInput(
                jpeg: b,
                width: p.renderWidth,
                height: p.renderHeight,
                text: p.ocrText,
                lines: p.needsOcr ? null : await _ocrLines(repo, p.id),
              ),
          ],
          title: doc.title,
          size: pageSize,
          font: await _devanagariFontBytes(),
        )),
        'application/pdf',
      ),
    ],
    ExportFormat.jpg => [
      for (final (i, (_, b)) in images.indexed)
        ExportFile(images.length == 1 ? '$name.jpg' : '$name - ${i + 1}.jpg', b, 'image/jpeg'),
    ],
  };
}
