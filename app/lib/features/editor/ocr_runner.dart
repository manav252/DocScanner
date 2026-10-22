// Recognises text for pages whose OCR is missing or outdated, one page at a
// time, and stores it through the DocumentController.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
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

  /// Longest side fed to OCR: plenty for text, keeps Tesseract fast.
  static const maxSide = 2400;

  bool get available => _ref.read(textRecognizerProvider).isAvailable;

  /// OCR every stale page of [docId] (or just [pageIds]). Returns how many pages
  /// were recognised. Concurrent calls for the same document share the work.
  Future<int> run(String docId, {Set<String>? pageIds, void Function(OcrProgress)? onProgress}) {
    final language = _ref.read(appSettingsProvider).ocrLanguage.code;
    final key = '$docId:$language:${pageIds?.join(',') ?? '*'}';
    // Block body: whenComplete would otherwise await the removed future (itself) forever.
    return _running[key] ??= _run(docId, pageIds, language, onProgress).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<int> _run(String docId, Set<String>? pageIds, String language, void Function(OcrProgress)? onProgress) async {
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
        onProgress?.call(OcrProgress(done, todo.length));
        final render = await repo.pageImage(p.id, PageImage.render);
        if (render == null) continue;
        final input = p.renderWidth > maxSide || p.renderHeight > maxSide
            ? await engine.processEncoded(render, PageEdits.none, maxSide: maxSide, quality: 92)
            : render;
        final result = cleanOcr(await recognizer.recognize(input, language: language));
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
