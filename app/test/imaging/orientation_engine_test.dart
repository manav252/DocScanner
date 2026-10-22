// The crop must match the selection for portrait, landscape, EXIF-rotated and
// very large photos (real native engine, real photos).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/scan_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'fixtures.dart';

final dir = '${fixturesDir.path}/orientation';
final spec = jsonDecode(File('$dir/orientation.json').readAsStringSync()) as Map<String, dynamic>;

/// Mean absolute difference between two same-size images (after resizing [b] to [a]).
double meanDiff(Uint8List a, Uint8List b) {
  final ma = cv.imdecode(a, cv.IMREAD_GRAYSCALE), mb0 = cv.imdecode(b, cv.IMREAD_GRAYSCALE);
  final mb = cv.resize(mb0, (ma.cols, ma.rows), interpolation: cv.INTER_AREA);
  final da = ma.data, db = mb.data;
  var s = 0;
  for (var i = 0; i < da.length; i++) {
    s += (da[i] - db[i]).abs();
  }
  return s / da.length;
}

void main() {
  late ScanEngine engine;
  setUpAll(() async {
    engine = ScanEngine();
    await engine.ready;
  });
  tearDownAll(() => engine.dispose());

  for (final name in ['portrait.jpg', 'landscape.jpg', 'exif_rotated.jpg', 'large.jpg']) {
    test('$name: upright size, detection and warp of the detected page', () async {
      final c = spec[name] as Map<String, dynamic>;
      final (w, h) = ((c['size'] as List)[0] as int, (c['size'] as List)[1] as int);
      final photo = await engine.normalizeEncoded(File('$dir/$name').readAsBytesSync());
      // Upright, and capped at 4000 px on the longest side.
      final scale = (w > h ? w : h) > 4000 ? 4000 / (w > h ? w : h) : 1.0;
      expect((photo.width, photo.height), ((w * scale).round(), (h * scale).round()));
      final d = await engine.detectEncoded(photo.bytes);
      expect((d.width, d.height), (photo.width, photo.height), reason: 'detector sees the same pixels');
      expect(d.detection.found, isTrue);
      final expected = [for (final p in c['corners'] as List) Pt(((p as List)[0] as num) * scale, (p[1] as num) * scale)];
      final err = maxCornerError(d.detection.corners, orderCorners(expected));
      expect(err, lessThan(0.01 * (photo.width + photo.height)), reason: 'corner error $err px');
    });
  }

  test('the warp crops exactly the selected area', () async {
    final photo = await engine.normalizeEncoded(File('$dir/portrait.jpg').readAsBytesSync());
    // An axis-aligned selection: the warp must equal a plain crop of that rectangle.
    const sel = [Pt(300, 900), Pt(900, 900), Pt(900, 1300), Pt(300, 1300)];
    final warped = await engine.warpEncoded(photo.bytes, sel);
    final m = cv.imdecode(photo.bytes, cv.IMREAD_COLOR);
    final crop = m.region(cv.Rect(300, 900, 601, 401)).clone();
    final (_, cropJpg) = cv.imencode('.jpg', crop);
    final out = cv.imdecode(warped, cv.IMREAD_COLOR);
    expect((out.cols, out.rows), (600, 400));
    expect(meanDiff(Uint8List.fromList(cropJpg), warped), lessThan(4));
  });

  test('EXIF-rotated photo: the same selection gives the same crop as the upright photo', () async {
    final upright = await engine.normalizeEncoded(File('$dir/portrait.jpg').readAsBytesSync());
    final rotated = await engine.normalizeEncoded(File('$dir/exif_rotated.jpg').readAsBytesSync());
    const sel = [Pt(250, 300), Pt(950, 330), Pt(900, 1200), Pt(200, 1150)];
    final a = await engine.warpEncoded(upright.bytes, sel);
    final b = await engine.warpEncoded(rotated.bytes, sel);
    expect(meanDiff(a, b), lessThan(4), reason: 'orientation applied before the corners are used');
  });

  test('very large photo: selection in full-size pixels scales with the cap', () async {
    final big = await engine.normalizeEncoded(File('$dir/large.jpg').readAsBytesSync());
    final small = await engine.normalizeEncoded(File('$dir/portrait.jpg').readAsBytesSync());
    final s = big.width / small.width; // 2.5
    const sel = [Pt(300, 900), Pt(900, 900), Pt(900, 1300), Pt(300, 1300)];
    final a = await engine.warpEncoded(small.bytes, sel);
    final b = await engine.warpEncoded(big.bytes, [for (final p in sel) Pt(p.x * s, p.y * s)]);
    expect(meanDiff(a, b), lessThan(6));
  });
}
