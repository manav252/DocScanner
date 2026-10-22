// Build export files (PDF or JPGs) from a document's rendered pages.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/document_repository.dart';
import '../../data/models.dart';
import '../../services/export/pdf_builder.dart';
import '../../services/export/share_service.dart';
import '../../services/ocr/ocr_result.dart';

enum ExportFormat { pdf, jpg }

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

  Future<List<ExportFile>> build(ScanDocument doc, {required ExportFormat format, PdfPageSize pageSize = PdfPageSize.fit}) =>
      buildExport(_ref.read(documentRepositoryProvider), doc, format: format, pageSize: pageSize);
}

final exporterProvider = Provider<Exporter>(Exporter.new);

Future<List<ExportFile>> buildExport(
  DocumentRepository repo,
  ScanDocument doc, {
  required ExportFormat format,
  PdfPageSize pageSize = PdfPageSize.fit,
}) async {
  final name = safeFileName(doc.title);
  final images = <(ScanPage, Uint8List)>[];
  for (final p in doc.pages) {
    final bytes = await repo.pageImage(p.id, PageImage.render);
    if (bytes != null) images.add((p, bytes));
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
