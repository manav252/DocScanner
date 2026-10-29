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
/// For each side of [q]: does it lie along the photo's border (both ends
/// within frameMargin of the same edge of the unpadded [w] x [h] photo)?
List<bool> onFrame(List<Pt> q, int w, int h) {
  final m = _P.frameMargin * math.max(w, h);
  final lo = _P.pad + m, hx = w - 1 - _P.pad - m, hy = h - 1 - _P.pad - m;
  return [
    for (var i = 0; i < 4; i++)
      () {
        final a = q[i], b = q[(i + 1) % 4];
        return (a.x <= lo && b.x <= lo) ||
            (a.x >= hx && b.x >= hx) ||
            (a.y <= lo && b.y <= lo) ||
            (a.y >= hy && b.y >= hy);
      }(),
  ];
}

ScoredQuad? scoreQuad(List<Pt>? contour, double contourArea, List<Pt> q, double imgArea, GrayImage img) {
  q = orderCorners(q);
  if (!isConvex(q)) return null;
  final qArea = polygonArea(q);
  if (qArea < _P.minAreaRatio * imgArea || (contour != null && contourArea / qArea < _P.minFillRatio)) return null;
  // Never the photo itself (a checked cloth or the padding forms its border).
  final frameSides = onFrame(q, img.width, img.height).where((f) => f).length;
  if (qArea > _P.maxArea * imgArea || frameSides > _P.maxFrameSides) return null;
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
  // A side along the photo's border is less likely a page edge than the
  // photo's own border meeting cloth: prefer outlines inside the photo.
  final score =
      math.sqrt(qArea / imgArea) *
      meanSupport *
      squareness *
      (1 - 0.1 * fit) *
      math.pow(_P.frameSideFactor, frameSides);
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

/// Proportions (mean of opposite sides) of an ID card or a standard paper
/// size? Perspective changes them a little, hence the tolerance.
bool knownRatio(List<Pt> q) {
  double side(int i) => q[(i + 1) % 4].distanceTo(q[i]);
  final a = side(0) + side(2), b = side(1) + side(3);
  if (a < 1e-6 || b < 1e-6) return false;
  final r = math.max(a, b) / math.min(a, b);
  return _P.docRatios.any((k) => (r / k - 1).abs() < _P.ratioTol);
}

/// Straight lines (rho, theta) through the set pixels of [mask] (w x h),
/// theta within houghTilt degrees of [centre]: a vote count over whole
/// degrees and pixels, strongest first, each suppressing its neighbours
/// (+-5 degrees, +-8 px). Exactly as in detect.py and scanner.js.
List<(double, double)> houghPeaks(Uint8List mask, int w, int h, int centre, int thr) {
  const tilt = _P.houghTilt, nT = 2 * tilt + 1;
  final rMax = math.sqrt(w * w + h * h).truncate() + 1, nR = 2 * rMax + 1;
  final acc = Int32List(nT * nR);
  final cs = Float64List(nT), sn = Float64List(nT);
  for (var k = 0; k < nT; k++) {
    final t = (centre - tilt + k) * (math.pi / 180);
    cs[k] = math.cos(t);
    sn[k] = math.sin(t);
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask[y * w + x] == 0) continue;
      for (var k = 0; k < nT; k++) {
        acc[k * nR + (x * cs[k] + y * sn[k] + 0.5).floor() + rMax]++;
      }
    }
  }
  final out = <(double, double)>[];
  while (out.length < _P.houghLines) {
    var bi = 0;
    for (var i = 1; i < acc.length; i++) {
      if (acc[i] > acc[bi]) bi = i; // first maximum
    }
    if (acc[bi] < thr) break;
    final k = bi ~/ nR, r = bi % nR;
    out.add(((r - rMax).toDouble(), (centre - tilt + k) * (math.pi / 180)));
    for (var kk = math.max(0, k - 5); kk <= math.min(nT - 1, k + 5); kk++) {
      for (var rr = math.max(0, r - 8); rr <= math.min(nR - 1, r + 8); rr++) {
        acc[kk * nR + rr] = 0;
      }
    }
  }
  return out;
}

/// Where two (rho, theta) lines cross, or null if they are parallel.
Pt? houghCross((double, double) l1, (double, double) l2) {
  final (r1, t1) = l1;
  final (r2, t2) = l2;
  final c1 = math.cos(t1), s1 = math.sin(t1), c2 = math.cos(t2), s2 = math.sin(t2);
  final det = c1 * s2 - s1 * c2;
  if (det.abs() < 1e-6) return null;
  return Pt((r1 * s2 - s1 * r2) / det, (c1 * r2 - r1 * c2) / det);
}

/// Lines pass: the best quad made of two roughly horizontal and two roughly
/// vertical [horiz]/[vert] lines (from [houghPeaks]), checked like any
/// straight-line quad; one shaped like a card or a sheet of paper scores
/// higher (lines make many rectangles: a card's printed boxes, too).
ScoredQuad? bestHoughQuad(List<(double, double)> horiz, List<(double, double)> vert, GrayImage img) {
  final w = img.width, h = img.height;
  final imgArea = (w * h).toDouble();
  ScoredQuad? best;
  for (var i = 0; i < horiz.length; i++) {
    for (var j = i + 1; j < horiz.length; j++) {
      for (var k = 0; k < vert.length; k++) {
        for (var m = k + 1; m < vert.length; m++) {
          final pts = [
            houghCross(horiz[i], vert[k]),
            houghCross(horiz[i], vert[m]),
            houghCross(horiz[j], vert[m]),
            houghCross(horiz[j], vert[k]),
          ];
          if (pts.any((p) => p == null)) continue;
          if (!pts.every((p) => p!.x >= -0.02 * w && p.x <= 1.02 * w && p.y >= -0.02 * h && p.y <= 1.02 * h)) continue;
          final r = scoreQuad(null, 0, [for (final p in pts) Pt(_f32(p!.x), _f32(p.y))], imgArea, img);
          if (r == null) continue;
          final score = r.score * (knownRatio(r.quad) ? _P.ratioBonus : 1.0);
          if (best == null || score > best.score) best = ScoredQuad(r.quad, score, curved: false);
        }
      }
    }
  }
  return best;
}

final _f32buf = Float32List(1);
double _f32(double v) => (_f32buf..[0] = v)[0];
