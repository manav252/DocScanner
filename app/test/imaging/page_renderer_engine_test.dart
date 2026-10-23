// End-to-end rendering with the real native engine.
import 'dart:io';

import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/imaging/page_edits.dart';
import 'package:docscanner/imaging/scan_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('photo -> flat -> filtered render + thumbnail', () async {
    final engine = ScanEngine();
    addTearDown(engine.dispose);
    await engine.ready;
    final repo = DocumentRepository(MemoryStore());
    final renderer = PageRenderer(engine, repo);
    final photo = File('${fixturesDir.path}/tilted_paper.jpg').readAsBytesSync();
    final det = await engine.detectEncoded(photo);

    var page = await renderer.createPage(
      source: photo,
      width: det.width,
      height: det.height,
      corners: det.detection.corners,
    );
    // Letter page ~ 0.77 aspect.
    expect(page.renderWidth / page.renderHeight, inInclusiveRange(0.7, 0.85));
    final (tw, th) = await PageRenderer.imageSize((await repo.pageImage(page.id, PageImage.thumb))!);
    expect([tw, th].reduce((a, b) => a > b ? a : b), PageRenderer.thumbMaxSide);

    page = await renderer.render(page.copyWith(edits: page.edits.rotatedClockwise()));
    expect(page.renderWidth, greaterThan(page.renderHeight), reason: 'landscape after rotating');
    page = await renderer.render(page.copyWith(edits: page.edits.copyWith(crop: const CropRect(0, 0, 0.5, 1))));
    expect(page.renderWidth / page.renderHeight, closeTo(0.5 * 1.29, 0.1));
  });
}
