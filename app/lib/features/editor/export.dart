// Build export files (PDF or JPGs) from a document's rendered pages.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cancel.dart';
import '../../core/providers.dart';
import '../../data/document_repository.dart';
import '../../data/id_card.dart';
import '../../data/models.dart';
import '../../services/export/pdf_builder.dart';
import '../../services/export/share_service.dart';
import '../../imaging/geometry.dart';
import '../../imaging/markup.dart';
import '../../services/ocr/ocr_result.dart';
import '../markup/markup_painter.dart';

enum ExportFormat { pdf, jpg }

/// "Hide the Aadhaar number" was asked for, but no page's text has one.
class AadhaarNumberNotFound implements Exception {
  const AadhaarNumberNotFound();
}

/// Markup that covers each of [boxes] (normalised to a [w]x[h] page) with
/// white and writes "XXXX XXXX" over it, burned in at export.
List<MarkupItem> _maskMarkup(List<({double l, double t, double r, double b})> boxes, int w, int h) {
  final short = math.min(w, h).toDouble();
  return [
    for (final (i, b) in boxes.indexed) ...[
      ShapeMarkup(
        id: 'mask-$i',
        kind: MarkupKind.whiteout,
        color: 0xFFFFFFFF,
        width: 0,
        a: Pt(b.l - 0.005, b.t - 0.01),
        b: Pt(b.r + 0.005, b.b + 0.01),
      ),
      TextMarkup(
        id: 'mask-text-$i',
        text: 'XXXX XXXX',
        x: (b.l + b.r) / 2,
        y: (b.t + b.b) / 2,
        width: (b.r - b.l) * w / short,
        size: 0.7 * (b.b - b.t) * h / short,
        bold: true,
      ),
    ],
  ];
}

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

Future<Uint8List> _pdfJob(_PdfJob j) =>
    buildPdf(j.pages, title: j.title, size: j.size, devanagariFont: j.font == null ? null : pw.Font.ttf(j.font!));

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
    bool maskAadhaar = false,
    CancelToken? cancel,
    void Function(int done, int total)? onPage,
  }) {
    final engine = _ref.read(scanEngineProvider);
    return buildExport(
      _ref.read(documentRepositoryProvider),
      doc,
      format: format,
      pageSize: pageSize,
      maskAadhaar: maskAadhaar,
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
  bool maskAadhaar = false,
  Future<Uint8List> Function(Uint8List jpeg, List<MarkupItem> items)? flatten,
  CancelToken? cancel,
  void Function(int done, int total)? onPage,
}) async {
  final name = safeFileName(doc.title);
  final images = <(ScanPage, Uint8List, String?, List<OcrLine>?)>[];
  var masked = 0;
  for (final (i, p) in doc.pages.indexed) {
    cancel?.check();
    onPage?.call(i, doc.pages.length);
    var bytes = await repo.pageImage(p.id, PageImage.render);
    if (bytes == null) continue;
    var text = p.ocrText;
    var lines = p.needsOcr ? null : await _ocrLines(repo, p.id);
    var markup = p.markup;
    if (maskAadhaar && lines != null) {
      // The first 8 digits: covered on the image, replaced by X in the text layer.
      final m = maskAadhaarNumber(lines);
      if (m.boxes.isNotEmpty) {
        masked++;
        markup = [...markup, ..._maskMarkup(m.boxes, p.renderWidth, p.renderHeight)];
        lines = m.lines;
        text = m.text;
      }
    }
    // Editable markup becomes part of the exported image.
    if (markup.isNotEmpty && flatten != null) bytes = await flatten(bytes, markup);
    images.add((p, bytes, text, lines));
  }
  if (images.isEmpty) throw StateError('This document has no pages');
  if (maskAadhaar && masked == 0) throw const AadhaarNumberNotFound();
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
            for (final (p, b, text, lines) in images)
              PdfPageInput(jpeg: b, width: p.renderWidth, height: p.renderHeight, text: text, lines: lines),
          ],
          title: doc.title,
          size: pageSize,
          font: await _devanagariFontBytes(),
        )),
        'application/pdf',
      ),
    ],
    ExportFormat.jpg => [
      for (final (i, (_, b, _, _)) in images.indexed)
        ExportFile(images.length == 1 ? '$name.jpg' : '$name - ${i + 1}.jpg', b, 'image/jpeg'),
    ],
  };
}
