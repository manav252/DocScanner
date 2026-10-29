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

  test('stability: never steady while moving; a brief miss is forgiven, a longer one resets', () {
    final t = StabilityTracker(window: 3);
    expect([for (var i = 0; i < 10; i++) t.update(shift(0.02 * i))].any((x) => x), isFalse);
    final jumpy = StabilityTracker(window: 5);
    expect([for (var i = 0; i < 20; i++) jumpy.update(shift(i.isEven ? 0 : 0.06))].any((x) => x), isFalse,
        reason: 'jumping between two places');
    t.reset();
    for (var i = 0; i < 3; i++) {
      t.update(base);
    }
    expect(t.isSteady, isTrue);
    expect(t.update(null), isFalse, reason: 'no capture on a frame without a page');
    expect(t.update(base), isTrue, reason: 'one missed frame does not restart the count');
    for (var i = 0; i < 3; i++) {
      t.update(null);
    }
    expect(t.isSteady, isFalse);
    expect(t.progress, 0);
  });

  test('stability: hand-held wobble and a one-frame wrong outline do not restart the count', () {
    final rng = math.Random(1), t = StabilityTracker(window: 8);
    final results = <bool>[];
    for (var i = 0; i < 10; i++) {
      // ~1 % wobble on every corner, plus one frame that jumps to another edge
      final d = i == 4 ? 0.15 : 0.01 * _gauss(rng);
      results.add(t.update(shift(d)));
    }
    expect(results.last, isTrue);
    expect(results.indexOf(true), lessThanOrEqualTo(8));
  });

  test('stability: a slow phone is steady after about a second, not after the full window', () {
    final t = StabilityTracker(window: 10);
    final results = [for (var i = 0; i < 5; i++) t.update(base, at: Duration(milliseconds: 250 * i))];
    expect(results, [false, false, false, false, true]);
    expect(t.progress, 1.0);
  });

  test('stability: a moved page restarts the count', () {
    final t = StabilityTracker(window: 4);
    for (var i = 0; i < 3; i++) {
      t.update(base);
    }
    for (var i = 0; i < 3; i++) {
      t.update(shift(0.2));
    }
    expect(t.isSteady, isFalse);
    expect(t.update(shift(0.2)), isFalse);
    expect(t.update(shift(0.2)), isFalse);
    expect(t.update(shift(0.2)), isTrue);
  });
}
