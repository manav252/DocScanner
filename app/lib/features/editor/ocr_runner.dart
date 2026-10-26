// Recognises text for pages whose OCR is missing or outdated, one page at a
// time, and stores it through the DocumentController.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/cancel.dart';
import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/page_edits.dart';
import '../../services/ocr/ocr_result.dart';
import 'document_controller.dart';

class OcrProgress {
  const OcrProgress(this.done, this.total);
  final int done, total;
}

class OcrRunner {
  OcrRunner(this._ref);
  final Ref _ref;
  final _running = <String, Future<int>>{};

  bool get available => _ref.read(textRecognizerProvider).isAvailable;

  /// OCR every stale page of [docId] (or just [pageIds]). Returns how many pages
  /// were recognised. Concurrent calls for the same document share the work.
  /// [cancel] stops after the current page (a run shared with another caller keeps going).
  Future<int> run(String docId, {Set<String>? pageIds, void Function(OcrProgress)? onProgress, CancelToken? cancel}) {
    final language = _ref.read(appSettingsProvider).ocrLanguage.code;
    final key = '$docId:$language:${pageIds?.join(',') ?? '*'}';
    // Block body: whenComplete would otherwise await the removed future (itself) forever.
    return _running[key] ??= _run(docId, pageIds, language, onProgress, cancel).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<int> _run(
    String docId,
    Set<String>? pageIds,
    String language,
    void Function(OcrProgress)? onProgress,
    CancelToken? cancel,
  ) async {
    final recognizer = _ref.read(textRecognizerProvider);
    if (!recognizer.isAvailable) return 0;
    final keepAlive = _ref.listen(documentProvider(docId), (_, _) {});
    try {
      final doc = await _ref.read(documentProvider(docId).future);
      final todo = [
        for (final p in doc.pages)
          if (p.needsOcrIn(language) && (pageIds == null || pageIds.contains(p.id))) p,
      ];
      final repo = _ref.read(documentRepositoryProvider);
      final engine = _ref.read(scanEngineProvider);
      var done = 0;
      for (final ScanPage p in todo) {
        cancel?.check();
        onProgress?.call(OcrProgress(done, todo.length));
        final render = await repo.pageImage(p.id, PageImage.render);
        if (render == null) continue;
        // Read the shadow-corrected page (Magic Color) whatever look the page
        // has, at its own rotation and crop so the line boxes match it.
        final flat = p.edits.filter == PageFilter.magicColor ? null : await repo.pageImage(p.id, PageImage.flat);
        final source = flat == null
            ? render
            : await engine.processEncoded(flat, p.edits.copyWith(filter: PageFilter.magicColor), quality: 92);
        Future<OcrResult> read({bool contrast = false}) async => cleanOcr(
          await recognizer.recognize(await engine.prepareOcrEncoded(source, contrast: contrast), language: language),
        );
        var result = await read();
        // Little text (faint print, an unusual background): try grayscale +
        // CLAHE too, and keep what either pass found.
        if (littleText(result)) result = mergeOcr(result, await read(contrast: true));
        await _ref.read(documentProvider(docId).notifier).setOcr(p.id, p.revision, result, language: language);
        done++;
      }
      onProgress?.call(OcrProgress(done, todo.length));
      return done;
    } finally {
      keepAlive.close();
    }
  }
}

final ocrRunnerProvider = Provider<OcrRunner>(OcrRunner.new);
