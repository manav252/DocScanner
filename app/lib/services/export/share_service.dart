// Share or save exported files.
//   Mobile : system share sheet (Save to Files / Drive / Mail / WhatsApp…)
//   Web    : Web Share API where the browser supports files, otherwise a download
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';

class ExportFile {
  const ExportFile(this.name, this.bytes, this.mimeType);
  final String name;
  final Uint8List bytes;
  final String mimeType;
}

class ShareService {
  const ShareService();

  /// Can [download] save straight to disk (web)?
  bool get canDownload => kIsWeb;

  Future<void> share(List<ExportFile> files, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(
      files: [for (final f in files) XFile.fromData(f.bytes, name: f.name, mimeType: f.mimeType)],
      fileNameOverrides: [for (final f in files) f.name],
      subject: subject,
      downloadFallbackEnabled: true,
    ));
  }

  /// Web: save each file to the Downloads folder.
  Future<void> download(List<ExportFile> files) async {
    for (final f in files) {
      downloadBytes(f.name, f.bytes, f.mimeType);
      // Browsers block bursts of downloads; space them out a little.
      if (files.length > 1) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}

/// File-name-safe version of a document title.
String safeFileName(String title) {
  final s = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return s.isEmpty ? 'Scan' : (s.length > 80 ? s.substring(0, 80) : s);
}
