// Candidate page outlines and how they are judged: a pure-Dart port of the
// scoring in scanner_core/detect.py (the reference). Used by the native
// detector (opencv_dart); the web detector (web/opencv/scanner.js) mirrors it.
//
// Every candidate quad that passes the sanity checks gets a score from its
// size, border support (a consistent brightness step across each side),
// squareness and outline fit; the best one wins, not simply the largest.
import 'dart:math' as math;
import 'dart:typed_data';

import 'detector_params.dart';
import 'geometry.dart';

typedef _P = DetectorParams;

/// A single-channel 8-bit image (row-major).
class GrayImage {
  const GrayImage(this.data, this.width, this.height);
  final Uint8List data;
  final int width, height;

  int at(double x, double y) => data[y.round().clamp(0, height - 1) * width + x.round().clamp(0, width - 1)];
}

/// A candidate that passed every check.
class ScoredQuad {
  const ScoredQuad(this.quad, this.score, {required this.curved});
  final List<Pt> quad;
  final double score;

  /// A side bows (book page): straight-line corner refinement would be wrong.
  final bool curved;
}

/// Corners as the outline's most top-left, top-right, bottom-right and
/// bottom-left points: still right when the sides bow (curved book pages).
List<Pt> extremePoints(List<Pt> c) {
  Pt pick(double Function(Pt) f, {required bool max}) => c.reduce((a, b) => (max ? f(b) > f(a) : f(b) < f(a)) ? b : a);
  double sum(Pt p) => p.x + p.y;
  double diff(Pt p) => p.x - p.y;
  return [pick(sum, max: false), pick(diff, max: true), pick(sum, max: true), pick(diff, max: false)];
}

/// Fit each side of [q] to the outline points nearest to it as a parabola
/// d(t) = a·t·(1−t) along the side's left normal (straight: a = 0). Returns per
/// side (a in px, 90th percentile residual in px).
List<(double, double)> sideFits(List<Pt> contour, List<Pt> q) {
  // Densify: CHAIN_APPROX_SIMPLE keeps only vertices.
  final p = <Pt>[];
  for (var i = 0; i < contour.length; i++) {
    final a = contour[i], b = contour[(i + 1) % contour.length];
    final k = math.max(1, (b.distanceTo(a) / 2).floor());
    for (var j = 0; j < k; j++) {
      p.add(a + (b - a) * (j / k));
    }
  }
  final ts = List.generate(4, (_) => Float64List(p.length));
  final ds = List.generate(4, (_) => Float64List(p.length));
  final dist = List.generate(4, (_) => Float64List(p.length));
  for (var i = 0; i < 4; i++) {
    final a = q[i], ab = q[(i + 1) % 4] - a;
    final len = ab.length + 1e-6;
    final u = ab * (1 / len), n = Pt(-ab.y / len, ab.x / len);
    for (var j = 0; j < p.length; j++) {
      final v = p[j] - a;
      final t = v.dot(u) / len, d = v.dot(n);
      ts[i][j] = t;
      ds[i][j] = d;
      dist[i][j] = t >= 0 && t <= 1 ? d.abs() : double.infinity;
    }
  }
  final out = <(double, double)>[];
  for (var i = 0; i < 4; i++) {
    final basis = <double>[], dm = <double>[];
    for (var j = 0; j < p.length; j++) {
      var side = 0;
      for (var k = 1; k < 4; k++) {
        if (dist[k][j] < dist[side][j]) side = k;
      }
      if (side == i && dist[i][j].isFinite) {
        basis.add(ts[i][j] * (1 - ts[i][j]));
        dm.add(ds[i][j]);
      }
    }
    if (dm.length < 6) {
      out.add((0, 0));
      continue;
    }
    final straight = percentile([for (final d in dm) d.abs()], 90);
    // The bow, robustly: the median over the side's middle.
    final ratios = [
      for (var j = 0; j < dm.length; j++)
        if (basis[j] > 0.1) dm[j] / basis[j],
    ];
    if (ratios.length < 4) {
      out.add((0, straight));
      continue;
    }
    final a = percentile(ratios, 50);
    final bowed = percentile([for (var j = 0; j < dm.length; j++) (dm[j] - a * basis[j]).abs()], 90);
    // Straight unless the curve fits clearly better.
    out.add(straight <= 1.25 * bowed ? (0, straight) : (a, bowed));
  }
  return out;
}

/// Share of each side (following its bow) where the image steps from inside
/// to outside the quad, in the same direction as along most of that side.
/// A page border does that all along; texture, stripes and the photo's own
/// frame do not.
List<double> edgeSupport(List<Pt> q, List<double> bows, GrayImage img) {
  final centre = (q[0] + q[1] + q[2] + q[3]) * 0.25;
  final out = <double>[];
  for (var i = 0; i < 4; i++) {
    final a = q[i], ab = q[(i + 1) % 4] - a;
    final len = ab.length + 1e-6;
    final left = Pt(-ab.y / len, ab.x / len);
    final n = left.dot(centre - a) > 0 ? left * -1 : left; // pointing outwards
    final d = Float64List(24);
    for (var s = 0; s < 24; s++) {
      final t = 0.1 + 0.8 * s / 23;
      final base = a + ab * t + left * (bows[i] * t * (1 - t));
      var best = 0.0;
      for (final o in const [-1.0, 0.0, 1.0]) {
        final pin = base + n * (o - _P.stepOffset), pout = base + n * (o + _P.stepOffset);
        final diff = (img.at(pin.x, pin.y) - img.at(pout.x, pout.y)).toDouble();
        if (diff.abs() > best.abs()) best = diff;
      }
      d[s] = best;
    }
    final sign = percentile(d.toList(), 50) >= 0 ? 1.0 : -1.0;
    out.add(d.where((v) => v * sign > _P.stepMin).length / 24);
  }
  return out;
}

/// Check candidate [q] (made from [contour], or from straight lines when
/// [contour] is null) and score it; null when it fails a check.
ScoredQuad? scoreQuad(List<Pt>? contour, double contourArea, List<Pt> q, double imgArea, GrayImage img) {
  q = orderCorners(q);
  if (!isConvex(q)) return null;
  final qArea = polygonArea(q);
  if (qArea < _P.minAreaRatio * imgArea || (contour != null && contourArea / qArea < _P.minFillRatio)) return null;
  final ang = interiorAngles(q);
  if (ang.reduce(math.min) < _P.minAngle || ang.reduce(math.max) > _P.maxAngle) return null;
  List<double> bows;
  double minSupport, fit;
  var bowRatio = 0.0;
  if (contour == null) {
    bows = [0, 0, 0, 0];
    minSupport = _P.minLineSupport;
    fit = 0.5; // no outline to compare with
  } else {
    final diag = q[2].distanceTo(q[0]);
    final fits = sideFits(contour, q);
    bows = [for (final f in fits) f.$1];
    for (var i = 0; i < 4; i++) {
      bowRatio = math.max(bowRatio, bows[i].abs() / 4 / q[(i + 1) % 4].distanceTo(q[i]));
    }
    final resid = fits.map((f) => f.$2).reduce(math.max);
    if (resid > _P.maxEdgeDeviation * diag || bowRatio > _P.maxBow) return null;
    minSupport = _P.minSupport;
    fit = resid / (_P.maxEdgeDeviation * diag); // 0 = perfect, 1 = at the limit
  }
  // Along the fitted bow or the straight side, whichever has the border.
  final bowed = edgeSupport(q, bows, img), straight = edgeSupport(q, const [0, 0, 0, 0], img);
  final support = [for (var i = 0; i < 4; i++) math.max(bowed[i], straight[i])];
  if (support.reduce(math.min) < minSupport) return null;
  final squareness = 1 - ang.map((a) => (a - 90).abs()).reduce((a, b) => a + b) / 4 / 90;
  final meanSupport = support.reduce((a, b) => a + b) / 4;
  // Tie-break between near-identical quads: the one hugging its outline wins.
  final score = math.sqrt(qArea / imgArea) * meanSupport * squareness * (1 - 0.1 * fit);
  return ScoredQuad(q, score, curved: contour != null && bowRatio > _P.curvedBow);
}

/// Quads made of 4 long straight edges ([segments]: x1, y1, x2, y2), two
/// roughly opposite pairs, each extended to the others: finds a page whose
/// corners are hidden (fingers, other papers) or whose outline merges with
/// clutter.
List<List<Pt>> lineQuads(List<(double, double, double, double)> segments, int w, int h) {
  final segs = [...segments]
    ..sort(
      (a, b) => math
          .sqrt(math.pow(b.$3 - b.$1, 2) + math.pow(b.$4 - b.$2, 2))
          .compareTo(math.sqrt(math.pow(a.$3 - a.$1, 2) + math.pow(a.$4 - a.$2, 2))),
    );
  final lines = <(Pt, Pt, double)>[]; // point, unit direction, angle 0-180
  for (final (x1, y1, x2, y2) in segs) {
    var d = Pt(x2 - x1, y2 - y1);
    d = d * (1 / (d.length + 1e-6));
    final ang = (math.atan2(d.y, d.x) * 180 / math.pi) % 180;
    final p = Pt(x1, y1);
    // Skip near-duplicates (same direction, within 6 px).
    final dup = lines.any((l) {
      final da = (ang - l.$3).abs();
      final v = p - l.$1;
      return math.min(da, 180 - da) < 8 && (l.$2.x * v.y - l.$2.y * v.x).abs() < 6;
    });
    if (dup) continue;
    lines.add((p, d, ang));
    if (lines.length == _P.lineCount) break;
  }
  // Two families: roughly horizontal and roughly vertical (within 45°).
  final horiz = [
    for (final l in lines)
      if (l.$3 < 45 || l.$3 >= 135) l,
  ];
  final vert = [
    for (final l in lines)
      if (l.$3 >= 45 && l.$3 < 135) l,
  ];
  final quads = <List<Pt>>[];
  for (var i = 0; i < horiz.length; i++) {
    for (var j = i + 1; j < horiz.length; j++) {
      for (var k = 0; k < vert.length; k++) {
        for (var m = k + 1; m < vert.length; m++) {
          final pts = <Pt>[];
          for (final (a, b) in [(horiz[i], vert[k]), (vert[k], horiz[j]), (horiz[j], vert[m]), (vert[m], horiz[i])]) {
            final x = lineIntersection(a.$1, a.$1 + a.$2, b.$1, b.$1 + b.$2);
            if (x == null) break;
            pts.add(x);
          }
          if (pts.length == 4 &&
              pts.every((p) => p.x > -0.02 * w && p.x < 1.02 * w && p.y > -0.02 * h && p.y < 1.02 * h)) {
            quads.add(pts);
          }
        }
      }
    }
  }
  return quads;
}
