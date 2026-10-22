// Import images and PDFs into a document, page by page.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../imaging/geometry.dart';
import '../../imaging/page_edits.dart';
import '../../services/import/import_service.dart';
import '../editor/document_controller.dart';

class ImportProgress {
  const ImportProgress(this.done, this.label);
  final int done;
  final String label;
}

/// Adds every page of [files] to document [docId]. Photos get the page detected
/// and Magic Color applied; PDF pages and photos without a detectable page are
/// added as-is (corners can be adjusted later in the editor).
/// Returns the number of pages added.
class ImportFlow {
  const ImportFlow(this._ref);
  final Ref _ref;

  Future<int> importFiles(String docId, List<ImportedFile> files, {void Function(ImportProgress)? onProgress}) async {
    // Keep the (auto-disposing) document controller alive while importing.
    final keepAlive = _ref.listen(documentProvider(docId), (_, _) {});
    try {
      return await _import(docId, files, onProgress);
    } finally {
      keepAlive.close();
    }
  }

  Future<int> _import(String docId, List<ImportedFile> files, void Function(ImportProgress)? onProgress) async {
    final ref = _ref;
    final engine = ref.read(scanEngineProvider);
    final importer = ref.read(importServiceProvider);
    final doc = ref.read(documentProvider(docId).notifier);
    await ref.read(documentProvider(docId).future);
    var added = 0;
    for (final f in files) {
      if (f.isPdf) {
        await for (final png in importer.rasterizePdf(f.bytes)) {
          onProgress?.call(ImportProgress(added, '${f.name}: page ${added + 1}'));
          final (w, h) = await ref.read(pageRendererProvider).measure(png);
          await doc.addImage(png, w, h, fullBounds(w, h), edits: const PageEdits(filter: PageFilter.original));
          added++;
        }
      } else {
        onProgress?.call(ImportProgress(added, f.name));
        final r = await engine.detectEncoded(f.bytes);
        await doc.addImage(
          f.bytes,
          r.width,
          r.height,
          r.detection.corners,
          edits: PageEdits(filter: r.detection.found ? PageFilter.magicColor : PageFilter.original),
        );
        added++;
      }
    }
    await doc.settle();
    return added;
  }
}

final importFlowProvider = Provider<ImportFlow>(ImportFlow.new);
