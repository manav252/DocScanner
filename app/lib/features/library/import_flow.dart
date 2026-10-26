// Import images and PDFs into a document, page by page.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cancel.dart';
import '../../core/l10n.dart';
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
  const ImportResult(this.added, this.failed, {this.cancelled = false, this.reasons = const {}});
  final int added;
  final List<String> failed;

  /// Why each file in [failed] could not be opened (the error message).
  final Map<String, String> reasons;

  /// Stopped by the user; pages added until then are kept.
  final bool cancelled;
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
    CancelToken? cancel,
  }) async {
    // Keep the (auto-disposing) document controller alive while importing.
    final keepAlive = _ref.listen(documentProvider(docId), (_, _) {});
    try {
      return await _import(docId, files, onProgress, cancel);
    } finally {
      keepAlive.close();
    }
  }

  Future<ImportResult> _import(
    String docId,
    List<ImportedFile> files,
    void Function(ImportProgress)? onProgress,
    CancelToken? cancel,
  ) async {
    final ref = _ref;
    final engine = ref.read(scanEngineProvider);
    final importer = ref.read(importServiceProvider);
    final doc = ref.read(documentProvider(docId).notifier);
    await ref.read(documentProvider(docId).future);
    var added = 0;
    final failed = <String>[];
    final reasons = <String, String>{};
    for (final f in files) {
      if (cancel?.isCancelled ?? false) break;
      try {
        added += await _importOne(f, added, engine, importer, doc, onProgress, cancel);
      } on Cancelled {
        break;
      } catch (e) {
        failed.add(f.name);
        reasons[f.name] = '$e';
      }
    }
    await doc.settle();
    return ImportResult(added, failed, cancelled: cancel?.isCancelled ?? false, reasons: reasons);
  }

  /// Pages added from one file.
  Future<int> _importOne(
    ImportedFile f,
    int before,
    ScanEngine engine,
    ImportService importer,
    DocumentController doc,
    void Function(ImportProgress)? onProgress,
    CancelToken? cancel,
  ) async {
    var added = 0;
    {
      if (f.isPdf) {
        await for (final png in importer.rasterizePdf(f.bytes)) {
          cancel?.check();
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

/// "These files could not be opened…: a.pdf (password-protected PDF), b.jpg (…)".
String importFailures(AppLocalizations l, ImportResult r) => l.importSkipped(
  [
    for (final name in r.failed)
      switch (r.reasons[name] ?? '') {
        final e when e.contains('assword') => '$name (${l.importWhyPassword})',
        _ => '$name (${l.importWhyUnreadable})',
      },
  ].join(', '),
);

final importFlowProvider = Provider<ImportFlow>(ImportFlow.new);
