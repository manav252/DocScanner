// Pick images / PDFs from the device and turn PDFs into page images.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

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
    final files = await FilePicker.pickFiles(type: type, allowedExtensions: extensions);
    return [for (final f in files) ImportedFile(f.name, await f.xFile.readAsBytes())];
  }

  /// Render each PDF page to a PNG at [dpi].
  Stream<Uint8List> rasterizePdf(Uint8List pdf, {double dpi = 200}) async* {
    await for (final page in Printing.raster(pdf, dpi: dpi)) {
      yield await page.toPng();
    }
  }
}
