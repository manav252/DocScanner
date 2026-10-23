// Build export files (PDF or JPGs) from a document's rendered pages.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/document_repository.dart';
import '../../data/models.dart';
import '../../services/export/pdf_builder.dart';
import '../../services/export/share_service.dart';
import '../../imaging/markup.dart';
import '../../services/ocr/ocr_result.dart';
import '../markup/markup_painter.dart';

enum ExportFormat { pdf, jpg }

pw.Font? _deva;

/// Bundled Noto Sans Devanagari (OFL) so Hindi text is searchable in PDFs.
Future<pw.Font?> _devanagariFont() async {
  try {
    return _deva ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'));
  } catch (_) {
    return null; // without it, Hindi text is simply left out of the text layer
  }
}

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
  }) {
    final engine = _ref.read(scanEngineProvider);
    return buildExport(
      _ref.read(documentRepositoryProvider),
      doc,
      format: format,
      pageSize: pageSize,
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
}) async {
  final name = safeFileName(doc.title);
  final images = <(ScanPage, Uint8List)>[];
  for (final p in doc.pages) {
    var bytes = await repo.pageImage(p.id, PageImage.render);
    if (bytes == null) continue;
    // Editable markup becomes part of the exported image.
    if (p.markup.isNotEmpty && flatten != null) bytes = await flatten(bytes, p.markup);
    images.add((p, bytes));
  }
  if (images.isEmpty) throw StateError('This document has no pages');
  return switch (format) {
    ExportFormat.pdf => [
      ExportFile(
        '$name.pdf',
        await buildPdf(
          [
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
          devanagariFont: await _devanagariFont(),
        ),
        'application/pdf',
      ),
    ],
    ExportFormat.jpg => [
      for (final (i, (_, b)) in images.indexed)
        ExportFile(images.length == 1 ? '$name.jpg' : '$name - ${i + 1}.jpg', b, 'image/jpeg'),
    ],
  };
}
