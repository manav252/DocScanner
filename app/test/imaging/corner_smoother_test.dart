import 'dart:math' as math;

import 'package:docscanner/imaging/corner_smoother.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const base = [Pt(0.2, 0.1), Pt(0.8, 0.12), Pt(0.85, 0.9), Pt(0.15, 0.88)];

List<Pt> shift(double d) => [for (final p in base) Pt(p.x + d, p.y + d)];

double _gauss(math.Random r) => math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());

double _std(List<double> v) {
  final m = v.reduce((a, b) => a + b) / v.length;
  return math.sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length);
}

void main() {
  test('smoother reduces jitter', () {
    final rng = math.Random(0), s = CornerSmoother();
    final raw = <double>[], out = <double>[];
    for (var i = 0; i < 200; i++) {
      final c = [for (final p in base) Pt(p.x + 0.004 * _gauss(rng), p.y + 0.004 * _gauss(rng))];
      final o = s.update(c)!;
      if (i >= 20) {
        raw.add(c[0].x);
        out.add(o[0].x);
      }
    }
    expect(_std(out), lessThan(0.6 * _std(raw)));
  });

  test('smoother snaps on a big move', () {
    final s = CornerSmoother()..update(base);
    expect(s.update(shift(0.2)), shift(0.2));
  });

  test('smoother holds then drops', () {
    final s = CornerSmoother(holdFrames: 3)..update(base);
    for (var i = 0; i < 3; i++) {
      expect(s.update(null), base);
    }
    expect(s.update(null), isNull);
  });

  test('stability: steady after the window, progress fills up', () {
    final t = StabilityTracker(window: 5);
    final results = [for (var i = 0; i < 5; i++) t.update(shift(i.isEven ? 0 : 0.001))];
    expect(results, [false, false, false, false, true]);
    expect(t.progress, 1.0);
  });

  test('stability: never steady while moving, resets on miss', () {
    final t = StabilityTracker(window: 3);
    expect([for (var i = 0; i < 10; i++) t.update(shift(0.02 * i))].any((x) => x), isFalse);
    for (var i = 0; i < 3; i++) {
      t.update(base);
    }
    expect(t.isSteady, isTrue);
    t.update(null);
    expect(t.isSteady, isFalse);
    expect(t.progress, 0);
  });
}
