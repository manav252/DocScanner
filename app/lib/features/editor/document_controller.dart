// Edits one document: add/replace/delete/reorder pages, per-page edits, rename.
// Every change re-renders the affected page, saves the document and bumps its
// revision (so it gets synced). Operations are serialised.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/geometry.dart';
import '../../imaging/markup.dart';
import '../../imaging/page_edits.dart';
import '../../services/ocr/ocr_result.dart';

class DocumentController extends AsyncNotifier<ScanDocument> {
  DocumentController(this.id);
  final String id;

  Future<void> _queue = Future.value();

  @override
  Future<ScanDocument> build() async {
    final doc = await ref.watch(documentRepositoryProvider).get(id);
    if (doc == null || doc.deleted) throw StateError('Document not found');
    return doc;
  }

  /// Run [op] after previous operations; saves and publishes its result.
  Future<void> _mutate(Future<ScanDocument> Function(ScanDocument doc) op) {
    final next = _queue.then((_) async {
      final current = state.value ?? await future;
      final updated = await op(current);
      await ref.read(documentRepositoryProvider).save(updated);
      if (ref.mounted) state = AsyncData(updated);
    });
    _queue = next.catchError((Object _) {});
    return next;
  }

  ScanPage _page(ScanDocument d, String pageId) => d.pages.firstWhere((p) => p.id == pageId);

  List<ScanPage> _replace(ScanDocument d, ScanPage page) => [for (final p in d.pages) p.id == page.id ? page : p];

  Future<void> rename(String title) => _mutate((d) async => d.edit(title: title.trim().isEmpty ? d.title : title.trim()));

  /// Add a photo/imported image as a new page (at the end, or at [index]).
  Future<void> addImage(Uint8List source, int width, int height, List<Pt> corners,
      {PageEdits edits = const PageEdits(), int? index}) {
    return _mutate((d) async {
      final page = await ref.read(pageRendererProvider).createPage(
            source: source,
            width: width,
            height: height,
            corners: corners,
            edits: edits,
          );
      final pages = [...d.pages]..insert(index ?? d.pages.length, page);
      return d.edit(pages: pages);
    });
  }

  /// Retake: swap the photo of [pageId], keeping its position and filter.
  Future<void> replaceImage(String pageId, Uint8List source, int width, int height, List<Pt> corners) {
    return _mutate((d) async {
      final page = await ref.read(pageRendererProvider).replaceSource(
            _page(d, pageId),
            source: source,
            width: width,
            height: height,
            corners: corners,
          );
      return d.edit(pages: _replace(d, page));
    });
  }

  Future<void> setCorners(String pageId, List<Pt> corners) => _mutate((d) async {
        final p = _page(d, pageId);
        final page = await ref
            .read(pageRendererProvider)
            .render(p.copyWith(corners: orderCorners(corners), edits: p.edits.copyWith(crop: CropRect.full)), reflatten: true);
        return d.edit(pages: _replace(d, page));
      });

  Future<void> _setEdits(String pageId, PageEdits Function(PageEdits) change) => _mutate((d) async {
        final p = _page(d, pageId);
        final edits = change(p.edits);
        if (edits == p.edits) return d;
        final page = await ref.read(pageRendererProvider).render(p.copyWith(edits: edits));
        return d.edit(pages: _replace(d, page));
      });

  Future<void> setFilter(String pageId, PageFilter f) => _setEdits(pageId, (e) => e.copyWith(filter: f));

  /// Rotate 90 degrees clockwise; markup turns with the page.
  Future<void> rotate(String pageId) => _mutate((d) async {
        final p = _page(d, pageId);
        final page = await ref.read(pageRendererProvider).render(p.copyWith(
              edits: p.edits.rotatedClockwise(),
              markup: [for (final m in p.markup) m.rotatedClockwise()],
            ));
        return d.edit(pages: _replace(d, page));
      });

  /// Crop; markup keeps its place on the page content.
  Future<void> setCrop(String pageId, CropRect crop) => _mutate((d) async {
        final p = _page(d, pageId);
        final next = crop.normalized();
        if (next == p.edits.crop) return d;
        var page = await ref.read(pageRendererProvider).render(p.copyWith(edits: p.edits.copyWith(crop: next)));
        if (p.markup.isNotEmpty && page.renderWidth > 0 && p.renderWidth > 0) {
          final oldUnit = math.min(p.renderWidth, p.renderHeight), newUnit = math.min(page.renderWidth, page.renderHeight);
          final from = p.edits.crop.toJson(), to = next.toJson();
          page = page.copyWith(markup: [for (final m in p.markup) m.recropped(from, to, oldUnit / newUnit)]);
        }
        return d.edit(pages: _replace(d, page));
      });

  /// Replace a page's markup (from the markup editor).
  Future<void> setMarkup(String pageId, List<MarkupItem> markup) =>
      _mutate((d) async => d.edit(pages: _replace(d, _page(d, pageId).copyWith(markup: markup))));

  Future<void> applyFilterToAll(PageFilter f) => _mutate((d) async {
        final renderer = ref.read(pageRendererProvider);
        final pages = <ScanPage>[];
        for (final p in d.pages) {
          pages.add(p.edits.filter == f ? p : await renderer.render(p.copyWith(edits: p.edits.copyWith(filter: f))));
        }
        return d.edit(pages: pages);
      });

  Future<void> deletePage(String pageId) => _mutate((d) async {
        await ref.read(documentRepositoryProvider).deletePageImages(pageId);
        return d.edit(pages: [for (final p in d.pages) if (p.id != pageId) p]);
      });

  /// Move the page at [oldIndex] so it ends up at [newIndex] (onReorderItem semantics).
  Future<void> reorder(int oldIndex, int newIndex) => _mutate((d) async {
        final pages = [...d.pages];
        pages.insert(newIndex, pages.removeAt(oldIndex));
        return d.edit(pages: pages);
      });

  /// Store OCR for [pageId] if the page has not been re-rendered since [revision].
  Future<void> setOcr(String pageId, int revision, OcrResult result, {String language = 'eng'}) => _mutate((d) async {
        final p = d.pages.where((p) => p.id == pageId).firstOrNull;
        if (p == null || p.revision != revision) return d;
        await ref
            .read(documentRepositoryProvider)
            .putPageOcr(pageId, Uint8List.fromList(utf8.encode(jsonEncode(result.toJson()))));
        return d.edit(
            pages: _replace(d, p.copyWith(ocrText: result.text, ocrRevision: revision, ocrLanguage: language)));
      });

  /// Mark a page's text as outdated so it is recognised again.
  Future<void> invalidateOcr(String pageId) => _mutate((d) async {
        final p = _page(d, pageId);
        return p.needsOcr ? d : d.edit(pages: _replace(d, p.copyWith(ocrRevision: -1)));
      });

  /// Wait for queued operations (tests, export).
  Future<void> settle() => _queue;
}

final documentProvider =
    AsyncNotifierProvider.autoDispose.family<DocumentController, ScanDocument, String>(DocumentController.new);

/// A stored page image; [revision] makes the cache follow re-renders.
final pageImageProvider =
    FutureProvider.autoDispose.family<Uint8List?, ({String pageId, PageImage kind, int revision})>(
  (ref, key) => ref.watch(documentRepositoryProvider).pageImage(key.pageId, key.kind),
);
