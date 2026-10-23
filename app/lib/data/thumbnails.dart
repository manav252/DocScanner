// Small page previews for lists. They are made once when a page is rendered
// (PageRenderer, 360 px JPEG) and stored next to the page; this service reads
// them through an in-memory cache, never decodes full pages for a list, rebuilds
// a missing one from the rendered page, and gives up after a timeout so a card
// can show a placeholder instead of an endless spinner.
import 'dart:async';
import 'dart:typed_data';

import '../imaging/page_edits.dart';
import '../imaging/scan_engine.dart';
import 'document_repository.dart';
import 'models.dart';
import 'page_renderer.dart';

class ThumbnailService {
  ThumbnailService(this._repo, this._engine, {this.timeout = const Duration(seconds: 8), this.capacity = 400});

  final DocumentRepository _repo;
  final ScanEngine _engine;
  final Duration timeout;

  /// Thumbnails kept in memory (~15-30 KB each).
  final int capacity;

  final _cache = <String, Uint8List>{}; // insertion-ordered: least recently used first
  final _inFlight = <String, Future<Uint8List?>>{};
  Future<void> _queue = Future.value();

  /// The thumbnail of page [pageId] at [revision]: memory, then storage, then
  /// rebuilt from the page. Null when the page has no image at all. Throws
  /// [TimeoutException] when storage does not answer in time.
  Future<Uint8List?> thumb(String pageId, int revision) {
    final key = '$pageId@$revision';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recently used
      return Future.value(hit);
    }
    // Block body: an arrow would return the removed future (this one) and whenComplete would wait on itself.
    return _inFlight[key] ??= _load(pageId, key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<Uint8List?> _load(String pageId, String key) async {
    var bytes = await _repo.pageImage(pageId, PageImage.thumb).timeout(timeout);
    bytes ??= await regenerate(pageId).timeout(timeout * 4);
    if (bytes != null) _remember(key, bytes);
    return bytes;
  }

  void _remember(String key, Uint8List bytes) {
    _cache[key] = bytes;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Forget cached previews of a page (after a re-render or delete).
  void evict(String pageId) => _cache.removeWhere((k, _) => k.startsWith('$pageId@'));

  /// Rebuild a missing thumbnail from the rendered page (one at a time, so a
  /// library full of old documents does not hog the image worker).
  Future<Uint8List?> regenerate(String pageId) {
    final done = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      try {
        final render = await _repo.pageImage(pageId, PageImage.render);
        if (render == null) {
          done.complete(null);
          return;
        }
        final thumb = await _engine.processEncoded(
          render,
          PageEdits.none,
          maxSide: PageRenderer.thumbMaxSide,
          quality: 80,
        );
        await _repo.putPageImage(pageId, PageImage.thumb, thumb);
        done.complete(thumb);
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  /// Background upkeep: make thumbnails that are missing and remove files of
  /// pages no document uses any more. Returns (thumbnails made, orphan pages removed).
  Future<(int, int)> repair() async {
    var made = 0;
    for (final doc in await _repo.listAll()) {
      if (doc.deleted) continue;
      for (final p in doc.pages) {
        if (await _repo.pageImage(p.id, PageImage.thumb) != null) continue;
        if (await regenerate(p.id).catchError((Object _) => null) != null) made++;
      }
    }
    final orphans = await _repo.orphanPageIds();
    for (final id in orphans) {
      await _repo.deletePageImages(id);
    }
    await _repo.forgetOrphans(orphans);
    return (made, orphans.length);
  }
}
