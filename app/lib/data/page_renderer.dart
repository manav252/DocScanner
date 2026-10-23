// Turns a page's source photo + corners + edits into its stored images:
//   source --warp(corners)--> flat --edits--> render --downscale--> thumb
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:uuid/uuid.dart';

import '../imaging/geometry.dart';
import '../imaging/page_edits.dart';
import '../imaging/scan_engine.dart';
import 'document_repository.dart';
import 'image_header.dart';
import 'models.dart';

class PageRenderer {
  PageRenderer(this._engine, this._repo, {Future<(int, int)> Function(Uint8List)? measure})
    : _measure = measure ?? imageSize;
  final ScanEngine _engine;
  final DocumentRepository _repo;
  final Future<(int, int)> Function(Uint8List) _measure;

  /// Longest side of the flattened page: 2480 px is ~210 dpi on the long side of
  /// A4 (300 dpi across): sharp text. Measured with tool/pdf_size_test.dart, 3200 px
  /// at JPEG 90 made a 10-page PDF of 14.0 MB; 2480 px at 85 makes 8.1 MB.
  static const flatMaxSide = 2480;

  /// JPEG quality of the rendered page (what is shown and exported).
  static const renderQuality = 85;
  static const thumbMaxSide = 360;

  /// Store a new page from a photo/imported image and render it.
  Future<ScanPage> createPage({
    required Uint8List source,
    required int width,
    required int height,
    required List<Pt> corners,
    PageEdits edits = const PageEdits(),
  }) async {
    final page = ScanPage(
      id: const Uuid().v4(),
      sourceWidth: width,
      sourceHeight: height,
      corners: orderCorners(corners),
      edits: edits,
    );
    await _repo.putPageImage(page.id, PageImage.source, source);
    return render(page, reflatten: true);
  }

  /// Replace a page's photo (retake), keeping its id and edits.
  Future<ScanPage> replaceSource(
    ScanPage page, {
    required Uint8List source,
    required int width,
    required int height,
    required List<Pt> corners,
  }) async {
    await _repo.putPageImage(page.id, PageImage.source, source);
    final replaced = ScanPage(
      id: page.id,
      sourceWidth: width,
      sourceHeight: height,
      corners: orderCorners(corners),
      edits: page.edits.copyWith(crop: CropRect.full),
      revision: page.revision,
      sourceVersion: page.sourceVersion + 1,
    );
    return render(replaced, reflatten: true);
  }

  /// Re-render after an edit. [reflatten] is needed when the corners or source changed.
  Future<ScanPage> render(ScanPage page, {bool reflatten = false}) async {
    Uint8List? flat = reflatten ? null : await _repo.pageImage(page.id, PageImage.flat);
    if (flat == null) {
      final source = await _repo.pageImage(page.id, PageImage.source);
      if (source == null) throw StateError('page ${page.id} has no source image');
      flat = await _engine.warpEncoded(source, page.corners, maxSide: flatMaxSide);
      await _repo.putPageImage(page.id, PageImage.flat, flat);
    }
    final render = await _engine.processEncoded(flat, page.edits, quality: renderQuality);
    final thumb = await _engine.processEncoded(render, PageEdits.none, maxSide: thumbMaxSide, quality: 80);
    await _repo.putPageImage(page.id, PageImage.render, render);
    await _repo.putPageImage(page.id, PageImage.thumb, thumb);
    final (w, h) = await _measure(render);
    return page.copyWith(revision: page.revision + 1, renderWidth: w, renderHeight: h);
  }

  /// Pixel size of an encoded image (injectable for tests).
  Future<(int, int)> measure(Uint8List encoded) => _measure(encoded);

  /// Pixel size of an encoded image: header parse, falling back to a full decode.
  static Future<(int, int)> imageSize(Uint8List encoded) async {
    final fromHeader = imageHeaderSize(encoded);
    if (fromHeader != null) return fromHeader;
    final codec = await ui.instantiateImageCodec(encoded); // works on every platform, incl. web
    final image = (await codec.getNextFrame()).image;
    final size = (image.width, image.height);
    image.dispose();
    codec.dispose();
    return size;
  }
}
