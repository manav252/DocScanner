// Builds a PDF from rendered page images (pure Dart: works on mobile and web).
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ocr/ocr_result.dart';

enum PdfPageSize {
  /// Page shaped like the scan (width of A4).
  fit('Fit to page'),
  a4('A4'),
  letter('US Letter');

  const PdfPageSize(this.label);
  final String label;
}

class PdfPageInput {
  const PdfPageInput({required this.jpeg, required this.width, required this.height, this.text, this.lines});
  final Uint8List jpeg;
  final int width, height;

  /// Recognised text; embedded invisibly so the PDF is searchable/copyable.
  final String? text;

  /// OCR lines with boxes: placed exactly over the words when available.
  final List<OcrLine>? lines;
}

/// The built-in PDF font only covers Latin-1 (and Devanagari when the Noto
/// fallback font is supplied): map common typography to ASCII and drop
/// anything else, so the text layer never breaks the export.
String pdfSafe(String s, {bool devanagari = false}) {
  const map = {
    '\u2018': "'",
    '\u2019': "'",
    '\u201c': '"',
    '\u201d': '"',
    '\u2013': '-',
    '\u2014': '-',
    '\u2026': '...',
    '\u2022': '*',
    '\u00a0': ' ',
    '\ufb01': 'fi',
    '\ufb02': 'fl',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final latin = r >= 0x20 && r <= 0xFF && (r < 0x7F || r >= 0xA0);
    final deva = devanagari && ((r >= 0x0900 && r <= 0x097F) || r == 0x200C || r == 0x200D);
    b.write(map[c] ?? (latin || deva ? c : (r == 0x0A ? '\n' : '')));
  }
  return b.toString();
}

const _invisibleBase = pw.TextStyle(renderingMode: PdfTextRenderingMode.invisible, fontSize: 10);

Future<Uint8List> buildPdf(
  List<PdfPageInput> pages, {
  String title = 'Scan',
  PdfPageSize size = PdfPageSize.fit,
  bool compress = true,
  pw.Font? devanagariFont,
}) async {
  final doc = pw.Document(title: title, creator: 'DocScanner', producer: 'DocScanner', compress: compress);
  // Invisible text layer: Helvetica for Latin text, Noto Sans Devanagari for Hindi.
  final invisible = devanagariFont == null ? _invisibleBase : _invisibleBase.copyWith(fontFallback: [devanagariFont]);
  final deva = devanagariFont != null;
  String safe(String t) => pdfSafe(t, devanagari: deva);
  for (final p in pages) {
    final landscape = p.width > p.height;
    final format = switch (size) {
      // Keep A4 width (or height for landscape) and the scan's aspect ratio.
      PdfPageSize.fit =>
        landscape
            ? PdfPageFormat(PdfPageFormat.a4.width * p.width / p.height, PdfPageFormat.a4.width)
            : PdfPageFormat(PdfPageFormat.a4.width, PdfPageFormat.a4.width * p.height / p.width),
      PdfPageSize.a4 => landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      PdfPageSize.letter => landscape ? PdfPageFormat.letter.landscape : PdfPageFormat.letter,
    };
    final image = pw.MemoryImage(p.jpeg);
    // Where the image lands on the page (contain, centred).
    final s = [format.width / p.width, format.height / p.height].reduce((a, b) => a < b ? a : b);
    final iw = p.width * s, ih = p.height * s;
    final ix = (format.width - iw) / 2, iy = (format.height - ih) / 2;
    final lines = [
      for (final l in p.lines ?? const <OcrLine>[])
        if (safe(l.text).trim().isNotEmpty) l,
    ];
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned(
              left: ix,
              top: iy,
              child: pw.Image(image, width: iw, height: ih, fit: pw.BoxFit.fill),
            ),
            // Invisible text (render mode 3) over the image: searchable, selectable, copyable.
            for (final l in lines)
              pw.Positioned(
                left: ix + l.left * iw,
                top: iy + l.top * ih,
                child: pw.SizedBox(
                  width: (l.width * iw).clamp(1, iw),
                  height: (l.height * ih).clamp(1, ih),
                  child: pw.FittedBox(
                    fit: pw.BoxFit.fill,
                    child: pw.Text(safe(l.text), style: invisible),
                  ),
                ),
              ),
            if (lines.isEmpty && p.text != null && safe(p.text!).trim().isNotEmpty)
              pw.Positioned(
                left: ix + 12,
                top: iy + 12,
                child: pw.SizedBox(
                  width: iw - 24,
                  height: ih - 24,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.topLeft,
                    child: pw.SizedBox(
                      width: iw - 24,
                      child: pw.Text(safe(p.text!), style: invisible),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
