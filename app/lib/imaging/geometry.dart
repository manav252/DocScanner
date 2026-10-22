// Pure-Dart geometry shared by every detector implementation (no OpenCV, no
// Flutter), so it runs on mobile, web and in plain unit tests.
import 'dart:math' as math;

/// A 2D point in image pixels (or normalised [0, 1] coordinates).
class Pt {
  const Pt(this.x, this.y);
  final double x, y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double s) => Pt(x * s, y * s);
  double dot(Pt o) => x * o.x + y * o.y;
  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Pt o) => (this - o).length;

  List<double> toJson() => [x, y];
  static Pt fromJson(List<dynamic> j) => Pt((j[0] as num).toDouble(), (j[1] as num).toDouble());

  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => 'Pt(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Result of a detection. [corners] are ordered TL, TR, BR, BL in source pixels.
class Detection {
  const Detection(this.corners, {required this.found, this.score = 0});
  final List<Pt> corners;
  final bool found;

  /// Fraction of the frame covered by the page (0 when not found).
  final double score;

  /// Corners divided by the image size, for drawing on any preview size.
  List<Pt> normalized(int width, int height) => [for (final p in corners) Pt(p.x / width, p.y / height)];
}

/// Order 4 points as TL, TR, BR, BL (clockwise on screen, y pointing down).
List<Pt> orderCorners(List<Pt> pts) {
  assert(pts.length == 4);
  final cx = pts.fold<double>(0, (s, p) => s + p.x) / 4;
  final cy = pts.fold<double>(0, (s, p) => s + p.y) / 4;
  final sorted = [...pts]..sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
  var start = 0;
  for (var i = 1; i < 4; i++) {
    if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) start = i;
  }
  return [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
}

List<Pt> fullBounds(int w, int h) => [Pt(0, 0), Pt(w - 1.0, 0), Pt(w - 1.0, h - 1.0), Pt(0, h - 1.0)];

double polygonArea(List<Pt> q) {
  var a = 0.0;
  for (var i = 0; i < q.length; i++) {
    final p = q[i], n = q[(i + 1) % q.length];
    a += p.x * n.y - n.x * p.y;
  }
  return a.abs() / 2;
}

bool isConvex(List<Pt> q) {
  var sign = 0;
  for (var i = 0; i < q.length; i++) {
    final a = q[i], b = q[(i + 1) % q.length], c = q[(i + 2) % q.length];
    final cr = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    if (cr.abs() < 1e-9) continue;
    final s = cr.sign.toInt();
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return sign != 0;
}

List<double> interiorAngles(List<Pt> q) => [
      for (var i = 0; i < 4; i++)
        () {
          final v1 = q[(i + 3) % 4] - q[i], v2 = q[(i + 1) % 4] - q[i];
          final cos = v1.dot(v2) / (v1.length * v2.length + 1e-6);
          return math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
        }(),
    ];

double _percentile(List<double> values, double p) {
  final s = [...values]..sort();
  final idx = p / 100 * (s.length - 1);
  final lo = idx.floor(), hi = idx.ceil();
  return s[lo] + (s[hi] - s[lo]) * (idx - lo);
}

/// 90th percentile distance from contour points to the nearest quad edge.
double edgeDeviation(List<Pt> contour, List<Pt> q) {
  final d = <double>[];
  for (final p in contour) {
    var best = double.infinity;
    for (var i = 0; i < 4; i++) {
      final a = q[i], ab = q[(i + 1) % 4] - a;
      final t = ((p - a).dot(ab) / (ab.dot(ab) + 1e-6)).clamp(0.0, 1.0);
      best = math.min(best, p.distanceTo(a + ab * t));
    }
    d.add(best);
  }
  return _percentile(d, 90);
}

Pt? lineIntersection(Pt p1, Pt p2, Pt p3, Pt p4) {
  final d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x);
  if (d.abs() < 1e-6) return null;
  final a = p1.x * p2.y - p1.y * p2.x;
  final b = p3.x * p4.y - p3.y * p4.x;
  return Pt((a * (p3.x - p4.x) - (p1.x - p2.x) * b) / d, (a * (p3.y - p4.y) - (p1.y - p2.y) * b) / d);
}

/// Recover a quad from a 5-8 vertex polygon whose corner(s) were clipped (e.g.
/// by a pen or finger lying across the page): keep the 4 longest sides and
/// intersect neighbouring ones.
List<Pt>? quadFromLongSides(List<Pt> p) {
  final n = p.length;
  if (n < 5 || n > 8) return null;
  final len = [for (var i = 0; i < n; i++) p[i].distanceTo(p[(i + 1) % n])];
  final keep = (List.generate(n, (i) => i)..sort((a, b) => len[b].compareTo(len[a]))).take(4).toList()..sort();
  final out = <Pt>[];
  for (var k = 0; k < 4; k++) {
    final i = keep[k], j = keep[(k + 1) % 4];
    final x = lineIntersection(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]);
    if (x == null) return null;
    out.add(x);
  }
  return out;
}

/// Robust 2D line fit (Huber-weighted total least squares, IRLS), the same
/// estimator as cv::fitLine(DIST_HUBER). Returns (point on line, unit direction).
(Pt, Pt) fitLineHuber(List<Pt> pts, {int iterations = 8}) {
  var w = List<double>.filled(pts.length, 1.0);
  late Pt c, dir;
  for (var it = 0; it < iterations; it++) {
    var sw = 0.0, cx = 0.0, cy = 0.0;
    for (var i = 0; i < pts.length; i++) {
      sw += w[i];
      cx += w[i] * pts[i].x;
      cy += w[i] * pts[i].y;
    }
    c = Pt(cx / sw, cy / sw);
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final dx = pts[i].x - c.x, dy = pts[i].y - c.y;
      sxx += w[i] * dx * dx;
      sxy += w[i] * dx * dy;
      syy += w[i] * dy * dy;
    }
    final theta = 0.5 * math.atan2(2 * sxy, sxx - syy); // principal axis
    dir = Pt(math.cos(theta), math.sin(theta));
    final n = Pt(-dir.y, dir.x);
    // Huber weights with OpenCV's default constant for DIST_HUBER (C = 1.345).
    for (var i = 0; i < pts.length; i++) {
      final r = (pts[i] - c).dot(n).abs();
      w[i] = r <= 1.345 ? 1.0 : 1.345 / r;
    }
  }
  return (c, dir);
}
