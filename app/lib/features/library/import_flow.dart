// Import images and PDFs into a document, page by page.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../imaging/geometry.dart';
import '../../imaging/page_edits.dart';
import '../../imaging/scan_engine.dart';
import '../../services/import/import_service.dart';
import '../editor/document_controller.dart';

class ImportProgress {
  const ImportProgress(this.done, this.label);
  final int done;
  final String label;
}

/// What an import did: pages added, and files that could not be opened
/// (corrupt, not an image/PDF, password-protected PDF…). Those are skipped.
class ImportResult {
  const ImportResult(this.added, this.failed);
  final int added;
  final List<String> failed;
}

/// Adds every page of [files] to document [docId]. Photos get the page detected
/// and Magic Color applied; PDF pages and photos without a detectable page are
/// added as-is (corners can be adjusted later in the editor). A file that cannot
/// be read is skipped and named in the result; the others are still imported.
class ImportFlow {
  const ImportFlow(this._ref);
  final Ref _ref;

  Future<ImportResult> importFiles(
    String docId,
    List<ImportedFile> files, {
    void Function(ImportProgress)? onProgress,
  }) async {
    // Keep the (auto-disposing) document controller alive while importing.
    final keepAlive = _ref.listen(documentProvider(docId), (_, _) {});
    try {
      return await _import(docId, files, onProgress);
    } finally {
      keepAlive.close();
    }
  }

  Future<ImportResult> _import(
    String docId,
    List<ImportedFile> files,
    void Function(ImportProgress)? onProgress,
  ) async {
    final ref = _ref;
    final engine = ref.read(scanEngineProvider);
    final importer = ref.read(importServiceProvider);
    final doc = ref.read(documentProvider(docId).notifier);
    await ref.read(documentProvider(docId).future);
    var added = 0;
    final failed = <String>[];
    for (final f in files) {
      try {
        added += await _importOne(f, added, engine, importer, doc, onProgress);
      } catch (_) {
        failed.add(f.name);
      }
    }
    await doc.settle();
    return ImportResult(added, failed);
  }

  /// Pages added from one file.
  Future<int> _importOne(
    ImportedFile f,
    int before,
    ScanEngine engine,
    ImportService importer,
    DocumentController doc,
    void Function(ImportProgress)? onProgress,
  ) async {
    var added = 0;
    {
      if (f.isPdf) {
        await for (final png in importer.rasterizePdf(f.bytes)) {
          onProgress?.call(ImportProgress(before + added, '${f.name}: page ${added + 1}'));
          final page = await engine.normalizeEncoded(png);
          await doc.addImage(
            page.bytes,
            page.width,
            page.height,
            fullBounds(page.width, page.height),
            edits: const PageEdits(filter: PageFilter.original),
          );
          added++;
        }
      } else {
        onProgress?.call(ImportProgress(before + added, f.name));
        // Upright, size-capped pixels for everything downstream (editor, warp, PDF).
        final photo = await engine.normalizeEncoded(f.bytes);
        final r = await engine.detectEncoded(photo.bytes);
        await doc.addImage(
          photo.bytes,
          r.width,
          r.height,
          r.detection.corners,
          edits: PageEdits(filter: r.detection.found ? PageFilter.magicColor : PageFilter.original),
        );
        added++;
      }
    }
    return added;
  }
}

final importFlowProvider = Provider<ImportFlow>(ImportFlow.new);
