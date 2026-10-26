// Native filters vs the Python reference outputs in shared/test_fixtures/filters.
import 'package:docscanner/imaging/native/opencv_filters.dart';
import 'package:docscanner/imaging/page_edits.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'fixtures.dart';

cv.Mat png(String name, [int flags = cv.IMREAD_UNCHANGED]) =>
    cv.imread('${fixturesDir.path}/filters/$name.png', flags: flags);

double meanAbsDiff(cv.Mat a, cv.Mat b) {
  expect((a.rows, a.cols, a.channels), (b.rows, b.cols, b.channels));
  final da = a.data, db = b.data;
  var s = 0;
  for (var i = 0; i < da.length; i++) {
    s += (da[i] - db[i]).abs();
  }
  return s / da.length;
}

void main() {
  final input = png('input', cv.IMREAD_COLOR);

  for (final (f, maxDiff) in [
    (PageFilter.original, 0.5),
    (PageFilter.grayscale, 1.0),
    (PageFilter.magicColor, 4.0),
    (PageFilter.bw, 6.0),
  ]) {
    test('${f.wireName} matches the Python reference', () {
      final out = applyFilter(input, f);
      final d = meanAbsDiff(out, png(f.wireName));
      expect(d, lessThan(maxDiff), reason: '${f.wireName}: mean abs diff ${d.toStringAsFixed(2)}');
    });
  }

  test('B&W is strictly black/white with a clean border', () {
    final out = blackAndWhite(input);
    expect(out.data.every((v) => v == 0 || v == 255), isTrue);
    expect(out.data.sublist(0, out.cols).every((v) => v == 255), isTrue);
  });

  test('applyEdits: rotate, crop and downscale', () {
    final r = applyEdits(input, const PageEdits(filter: PageFilter.original, quarterTurns: 1));
    expect((r.cols, r.rows), (input.rows, input.cols));
    final c = applyEdits(input, const PageEdits(filter: PageFilter.original, crop: CropRect(0.25, 0.5, 0.5, 0.25)));
    expect((c.cols - input.cols * 0.5).abs(), lessThanOrEqualTo(1));
    expect((c.rows - input.rows * 0.25).abs(), lessThanOrEqualTo(1));
    final t = applyEdits(input, const PageEdits(quarterTurns: 2), maxSide: 300);
    expect([t.cols, t.rows].reduce((a, b) => a > b ? a : b), 300);
  });

  test('crop follows a clockwise rotation', () {
    // Top-left quarter, rotated clockwise, becomes the top-right quarter.
    expect(const CropRect(0, 0, 0.5, 0.5).rotatedClockwise(), const CropRect(0.5, 0, 0.5, 0.5));
    const e = PageEdits(crop: CropRect(0.1, 0.2, 0.3, 0.4));
    var r = e;
    for (var i = 0; i < 4; i++) {
      r = r.rotatedClockwise();
    }
    expect(r.quarterTurns, 0);
    expect((r.crop.left - 0.1).abs() + (r.crop.top - 0.2).abs(), lessThan(1e-9));
  });

  test('PageEdits JSON round trip', () {
    const e = PageEdits(filter: PageFilter.bw, quarterTurns: 3, crop: CropRect(0.1, 0.2, 0.5, 0.6));
    expect(PageEdits.fromJson(e.toJson()), e);
  });

  test('OCR input: a small card is enlarged (at most 3x), a big page capped; contrast = grayscale', () {
    final card = cv.Mat.zeros(290, 456, cv.MatType.CV_8UC3);
    final big = prepareOcr(card);
    expect((big.cols, big.rows), (1368, 870), reason: '3x: text ~15 px -> ~45 px');
    final page = cv.Mat.zeros(3500, 2480, cv.MatType.CV_8UC3);
    expect(prepareOcr(page).rows, 2400);
    final mid = cv.Mat.zeros(2200, 1600, cv.MatType.CV_8UC3);
    expect((prepareOcr(mid).cols, prepareOcr(mid).rows), (1600, 2200), reason: 'already a good size');
    expect(prepareOcr(card, contrast: true).channels, 1);
  });
}
