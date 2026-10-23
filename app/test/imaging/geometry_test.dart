import 'dart:math' as math;

import 'package:docscanner/imaging/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('orderCorners', () {
    const rect = [Pt(100, 100), Pt(300, 100), Pt(300, 400), Pt(100, 400)];
    for (final deg in [0, 10, 30, 44, -20, -44]) {
      test('rotated $deg deg, any input order', () {
        final a = deg * math.pi / 180;
        const c = Pt(200, 250);
        final rot = [
          for (final p in rect)
            Pt(
              c.x + (p.x - c.x) * math.cos(a) - (p.y - c.y) * math.sin(a),
              c.y + (p.x - c.x) * math.sin(a) + (p.y - c.y) * math.cos(a),
            ),
        ];
        for (final perm in [
          [0, 1, 2, 3],
          [2, 0, 3, 1],
          [3, 2, 1, 0],
        ]) {
          final out = orderCorners([for (final i in perm) rot[i]]);
          for (var i = 0; i < 4; i++) {
            expect(out[i].distanceTo(rot[i]), lessThan(1e-9));
          }
        }
      });
    }
  });

  test('fitLineHuber ignores outliers', () {
    final pts = [
      for (var i = 0; i < 50; i++) Pt(i.toDouble(), 2 * i + 1.0),
      const Pt(10, 80), const Pt(20, -40), const Pt(30, 120), // outliers
    ];
    final (c, d) = fitLineHuber(pts);
    final (_, plain) = fitLineHuber(pts, iterations: 1); // first iteration = ordinary least squares
    final err = (d.y / d.x - 2).abs(), plainErr = (plain.y / plain.x - 2).abs();
    expect(err, lessThan(0.03)); // slope 2
    expect(err, lessThan(plainErr / 4)); // far more robust than least squares
    expect((c.y - (2 * c.x + 1)).abs(), lessThan(0.5)); // passes through the line
  });

  test('quadFromLongSides recovers a clipped corner', () {
    // 400x300 rectangle with the bottom-right corner cut off by a diagonal.
    const poly = [Pt(0, 0), Pt(400, 0), Pt(400, 250), Pt(350, 300), Pt(0, 300)];
    final q = orderCorners(quadFromLongSides(poly)!);
    expect(q[2].distanceTo(const Pt(400, 300)), lessThan(1e-6));
  });

  test('convexity and area', () {
    const sq = [Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(0, 10)];
    expect(isConvex(sq), isTrue);
    expect(isConvex(const [Pt(0, 0), Pt(10, 0), Pt(2, 2), Pt(0, 10)]), isFalse);
    expect(polygonArea(sq), 100);
  });
}
