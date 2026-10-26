// Pick images / PDFs from the device and turn PDFs into page images.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

import 'picker_options.dart';

class ImportedFile {
  const ImportedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;

  bool get isPdf => name.toLowerCase().endsWith('.pdf') || _startsWith(bytes, const [0x25, 0x50, 0x44, 0x46]); // %PDF

  static bool _startsWith(Uint8List b, List<int> magic) {
    if (b.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[i] != magic[i]) return false;
    }
    return true;
  }
}

class ImportService {
  const ImportService();

  /// Photo library (mobile) / image file picker (web). Multiple selection.
  Future<List<ImportedFile>> pickImages() => _pick(FileType.image);

  /// A DocScanner backup (.zip).
  Future<ImportedFile?> pickBackup() async {
    final files = await _pick(FileType.custom, const ['zip']);
    return files.isEmpty ? null : files.first;
  }

  /// PDF files only.
  Future<List<ImportedFile>> pickPdfs() => _pick(FileType.custom, const ['pdf']);

  /// Files app / file dialog: PDFs and images.
  Future<List<ImportedFile>> pickFiles() =>
      _pick(FileType.custom, const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif']);

  Future<List<ImportedFile>> _pick(FileType type, [List<String>? extensions]) async {
    final files = await FilePicker.pickFiles(type: type, allowedExtensions: extensions, webOptions: pickerWebOptions);
    return [for (final f in files) ImportedFile(f.name, await f.xFile.readAsBytes())];
  }

  /// Render each PDF page to a PNG at up to [dpi], with the long side capped at
  /// [maxSide] px (the size pages are kept at anyway).
  ///
  /// Each page is sized on its own: "photo to PDF" apps make pages as large as
  /// the photo (e.g. 3024×4032 pt). At a fixed 200 dpi that is an 8400×11200
  /// canvas (94 MP, ~380 MB): over Safari's 16.7 MP canvas limit and more memory
  /// than a low-end phone has, so the import failed on phones.
  Stream<Uint8List> rasterizePdf(Uint8List pdf, {double dpi = 200, int maxSide = 2480}) async* {
    final dpis = [
      await for (final p in Printing.raster(pdf, dpi: _probeDpi))
        pageDpi(p.width, p.height, dpi: dpi, maxSide: maxSide),
    ];
    // One pass per run of pages that share a dpi (usually the whole document):
    // each pass loads the PDF again (in a new pdf.js worker on the web).
    for (var start = 0; start < dpis.length;) {
      var end = start + 1;
      while (end < dpis.length && dpis[end] == dpis[start]) {
        end++;
      }
      await for (final page in Printing.raster(pdf, pages: [for (var i = start; i < end; i++) i], dpi: dpis[start])) {
        yield await page.toPng();
      }
      start = end;
    }
  }

  /// A cheap first pass that only finds out how big each page is.
  static const _probeDpi = 9.0;

  /// The dpi that renders a page measuring [probeW]×[probeH] px at [_probeDpi]
  /// with its long side at most [maxSide] px.
  static double pageDpi(int probeW, int probeH, {double dpi = 200, int maxSide = 2480}) {
    final longPt = math.max(probeW, probeH) * 72 / _probeDpi;
    return math.max(1, math.min(dpi, maxSide * 72 / longPt));
  }
}
