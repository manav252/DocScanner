// Curved pages (an open book, a bent sheet): trace the top and bottom page
// edges as curves so the page can be flattened with a grid warp instead of a
// single perspective warp. A pure-Dart port of scanner_core/warp.py (the
// reference); web/opencv/scanner.js mirrors it.
import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'quad_scoring.dart' show GrayImage;

/// A side bowing less than this (fraction of its length) counts as straight.
const curveMinBow = 0.015;

/// Tracing further than this from the straight side gives up.
const curveMaxBow = 0.15;

/// Points traced along each side.
const curveSamples = 48;

/// Edges are traced on a copy at most this big.
const curveWorkSide = 1000;

/// Brightness step (0-255) across the edge that counts as found.
const curveMinStep = 12.0;

/// d(t) = t(1−t)(c0 + c1·t): zero at both corners, one bend (c0) and a lean (c1).
double curveAt(List<double> c, double t) => t * (1 - t) * (c[0] + c[1] * t);

/// numpy.rint: halves round to the even neighbour.
int _rint(double v) {
  final r = v.roundToDouble();
  return ((v - v.truncateToDouble()).abs() == 0.5 ? 2 * (v / 2).roundToDouble() : r).toInt();
}

/// numpy.arange(start, stop) for floats.
List<double> _arange(double start, double stop) => [for (var i = 0; i < (stop - start).ceil(); i++) start + i];

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Brightness step from inside to outside the page at [p] (signed).
double _step(GrayImage g, Pt p, Pt outward) {
  int at(Pt q) => g.data[_rint(q.y).clamp(0, g.height - 1) * g.width + _rint(q.x).clamp(0, g.width - 1)];
  return (at(p - outward * 2) - at(p + outward * 2)).toDouble();
}

/// Trace the page edge between corners [a] and [b] (in [gray]'s pixels) and
/// fit d(t): its offset from the straight side along [outward]. Returns
/// [c0, c1]; zeros when the side is straight or its edge cannot be traced.
/// See side_curve in warp.py.
List<double> sideCurve(GrayImage gray, Pt a, Pt b, Pt outward) {
  final len = b.distanceTo(a);
  if (len < 20) return [0, 0];
  final maxOff = curveMaxBow * len;
  final window = math.max(3.0, 0.02 * len);
  final ts = [for (var i = 0; i < curveSamples; i++) 0.04 + (0.96 - 0.04) * i / (curveSamples - 1)];
  final chord = [for (final t in ts) a + (b - a) * t];
  final straight = [for (final p in chord) _step(gray, p, outward)];
  // Polarity from near the corners, where the edge is close to the straight
  // side (a bowed side already leaves it a little: search a small window).
  final near = _arange(-window, window + 1);
  final ends = [
    for (final base in [...chord.take(4), ...chord.skip(chord.length - 4)])
      () {
        var best = 0.0;
        var first = true;
        for (final o in near) {
          final s = _step(gray, base + outward * o, outward);
          if (first || s.abs() > best.abs()) best = s;
          first = false;
        }
        return best;
      }(),
  ];
  final sign = _median(ends) >= 0 ? 1.0 : -1.0;
  var prev = 0.0;
  final foundT = <double>[], foundD = <double>[];
  for (var i = 0; i < ts.length; i++) {
    final offs = _arange(math.max(-maxOff, prev - window), math.min(maxOff, prev + window) + 1);
    var k = -1;
    var best = double.negativeInfinity;
    for (var j = 0; j < offs.length; j++) {
      final s = sign * _step(gray, chord[i] + outward * offs[j], outward);
      if (s > best) {
        best = s;
        k = j;
      }
    }
    if (k >= 0 && best >= curveMinStep) {
      prev = offs[k];
      foundT.add(ts[i]);
      foundD.add(prev);
    }
  }
  if (foundT.length < 0.7 * ts.length) return [0, 0];
  var keep = List.filled(foundT.length, true);
  var c = [0.0, 0.0];
  for (var it = 0; it < 3; it++) {
    // Least squares on the kept points (2x2 normal equations), dropping outliers.
    var s11 = 0.0, s12 = 0.0, s22 = 0.0, r1 = 0.0, r2 = 0.0;
    for (var j = 0; j < foundT.length; j++) {
      if (!keep[j]) continue;
      final t = foundT[j], b1 = t * (1 - t), b2 = t * t * (1 - t);
      s11 += b1 * b1;
      s12 += b1 * b2;
      s22 += b2 * b2;
      r1 += b1 * foundD[j];
      r2 += b2 * foundD[j];
    }
    final det = s11 * s22 - s12 * s12;
    if (det.abs() < 1e-12) return [0, 0];
    c = [(r1 * s22 - r2 * s12) / det, (s11 * r2 - s12 * r1) / det];
    final res = [for (var j = 0; j < foundT.length; j++) (foundD[j] - curveAt(c, foundT[j])).abs()];
    final limit = math.max(
      2.0,
      2.5 *
          _median([
            for (var j = 0; j < res.length; j++)
              if (keep[j]) res[j],
          ]),
    );
    keep = [for (final r in res) r <= limit];
  }
  // Keep the curve only if the edge follows it clearly better than the chord.
  var onCurve = 0, onChord = 0;
  for (var i = 0; i < ts.length; i++) {
    if (sign * _step(gray, chord[i] + outward * curveAt(c, ts[i]), outward) >= curveMinStep) onCurve++;
    if (sign * straight[i] >= curveMinStep) onChord++;
  }
  final fc = onCurve / ts.length, fs = onChord / ts.length;
  if (fc < 0.8 || fc < fs + 0.15) return [0, 0];
  return c;
}

/// The outward unit normal of side [a]→[b] of a page centred at [centre].
Pt outwardNormal(Pt a, Pt b, Pt centre) {
  final ab = b - a;
  var n = Pt(-ab.y, ab.x) * (1 / (ab.length + 1e-9));
  if (n.dot(centre - a) > 0) n = n * -1;
  return n;
}

/// Fitted curves of the top and bottom edges (in the photo's pixels) of the
/// page with ordered [corners], traced on [small] (the photo scaled by
/// [scale], blurred); null when both are straight.
(List<double>, List<double>)? pageCurvesOn(GrayImage small, double scale, List<Pt> corners) {
  final q = orderCorners(corners);
  final qs = [for (final p in q) p * scale];
  final centre = (qs[0] + qs[1] + qs[2] + qs[3]) * 0.25;
  final curves = <List<double>>[];
  for (final (i, j) in const [(0, 1), (3, 2)]) {
    final c = sideCurve(small, qs[i], qs[j], outwardNormal(qs[i], qs[j], centre));
    curves.add([c[0] / scale, c[1] / scale]);
  }
  var bow = 0.0;
  for (final (k, (i, j)) in const [(0, 1), (3, 2)].indexed) {
    for (var s = 0; s <= 100; s++) {
      bow = math.max(bow, curveAt(curves[k], s / 100).abs() / q[j].distanceTo(q[i]));
    }
  }
  return bow < curveMinBow ? null : (curves[0], curves[1]);
}

/// The source position of every 8th output pixel (grid point j stands for
/// output pixel 8j + 3.5, as resizing the grid aligns pixel centres) for a
/// [w]x[h] flattened page: the perspective mapping [toPhoto] (output → photo)
/// plus, near the top and bottom, the traced edge curves. Returns
/// (map_x, map_y, grid width, grid height).
(Float32List, Float32List, int, int) gridMap(
  List<Pt> corners,
  (List<double>, List<double>) curves,
  int w,
  int h,
  Pt Function(double u, double v) toPhoto, {
  int step = 8,
}) {
  final src = orderCorners(corners);
  final gw = w ~/ step + 2, gh = h ~/ step + 2;
  final u = [for (var j = 0; j < gw; j++) j * step + (step - 1) / 2];
  final v = [for (var i = 0; i < gh; i++) i * step + (step - 1) / 2];
  final mx = Float32List(gw * gh), my = Float32List(gw * gh);
  final centre = (src[0] + src[1] + src[2] + src[3]) * 0.25;
  // Per column, each side's outward offset where that column meets it.
  final sides = <(Pt, List<double>, double)>[]; // (normal, offset per column, row)
  for (final (c, (a, b), row) in [(curves.$1, (src[0], src[1]), 0.0), (curves.$2, (src[3], src[2]), h - 1.0)]) {
    final ab = b - a, l2 = ab.dot(ab);
    final n = outwardNormal(a, b, centre);
    final d = [
      for (final uu in u)
        () {
          final e = toPhoto(uu, row);
          return curveAt(c, ((e - a).dot(ab) / l2).clamp(0.0, 1.0));
        }(),
    ];
    sides.add((n, d, row));
  }
  for (var i = 0; i < gh; i++) {
    final wTop = 1 - v[i] / (h - 1), wBottom = v[i] / (h - 1);
    for (var j = 0; j < gw; j++) {
      var p = toPhoto(u[j], v[i]);
      p = p + sides[0].$1 * (wTop * sides[0].$2[j]) + sides[1].$1 * (wBottom * sides[1].$2[j]);
      mx[i * gw + j] = p.x;
      my[i * gw + j] = p.y;
    }
  }
  return (mx, my, gw, gh);
}
