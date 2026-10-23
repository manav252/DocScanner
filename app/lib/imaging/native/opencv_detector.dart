// Document detection + perspective warp on Android/iOS via opencv_dart (FFI).
//
// A line-for-line port of scanner_core/detect.py (the reference) and of
// web/opencv/scanner.js:
//   downscale -> grayscale -> blur -> Canny -> dilate -> contours
//   -> largest convex 4-point polygon (approxPolyDP) -> order TL, TR, BR, BL
//   -> refine each side: strongest-gradient search + robust line fit
// Second pass with CLAHE + low Canny thresholds for low-contrast pages;
// full-frame fallback when nothing qualifies.
//
// All functions are synchronous and allocation-bounded so they can run on a
// background isolate for every preview frame.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../detector_params.dart';
import '../geometry.dart';

typedef _P = DetectorParams;

/// Detect the page in a BGR, BGRA or grayscale [image]. Corners are in source pixels.
Detection detectDocumentMat(cv.Mat image, {int maxDim = _P.maxDim}) {
  final w = image.cols, h = image.rows;
  if (w == 0 || h == 0) throw ArgumentError('empty image');
  final scale = math.min(1.0, maxDim / math.max(w, h));
  final small = scale < 1
      ? cv.resize(image, ((w * scale).round(), (h * scale).round()), interpolation: cv.INTER_AREA)
      : image.clone();
  final gray = switch (small.channels) {
    1 => small.clone(),
    3 => cv.cvtColor(small, cv.COLOR_BGR2GRAY),
    4 => cv.cvtColor(small, cv.COLOR_BGRA2GRAY),
    final n => throw ArgumentError('unsupported channel count $n'),
  };
  small.dispose();
  final result = _detectSmallGray(gray, w, h, scale);
  gray.dispose();
  return result;
}

/// Fast path for camera frames: the Y (luma) plane of a YUV420/NV21 frame is
/// already a grayscale image, so no colour conversion is needed.
Detection detectDocumentLuma(Uint8List luma, int width, int height, {int? rowStride, int maxDim = _P.maxDim}) {
  final stride = rowStride ?? width;
  final packed = stride == width ? luma.sublist(0, width * height) : Uint8List(width * height)
    ..setAll(0, [for (var r = 0; r < height; r++) ...luma.sublist(r * stride, r * stride + width)]);
  final m = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, packed);
  final d = detectDocumentMat(m, maxDim: maxDim);
  m.dispose();
  return d;
}

/// Decode JPEG/PNG bytes (gallery import, captured photo) and detect.
Detection detectDocumentBytes(Uint8List encoded) {
  final m = cv.imdecode(encoded, cv.IMREAD_COLOR);
  if (m.isEmpty) throw ArgumentError('could not decode image');
  final d = detectDocumentMat(m);
  m.dispose();
  return d;
}

Detection _detectSmallGray(cv.Mat graySmall, int w, int h, double scale) {
  const pad = _P.pad;
  final gray = cv.copyMakeBorder(graySmall, pad, pad, pad, pad, cv.BORDER_REPLICATE);
  try {
    for (final equalize in [false, true]) {
      final edges = _edgeMap(gray, equalize);
      final res = _bestQuad(edges);
      edges.dispose();
      if (res != null) {
        final q = _refineCorners(res.$1, gray)
            .map(
              (p) => Pt(
                ((p.x - pad + 0.5) / scale - 0.5).clamp(0, w - 1).toDouble(),
                ((p.y - pad + 0.5) / scale - 0.5).clamp(0, h - 1).toDouble(),
              ),
            )
            .toList();
        return Detection(q, found: true, score: res.$2);
      }
    }
    return Detection(fullBounds(w, h), found: false);
  } finally {
    gray.dispose();
  }
}

double _median(cv.Mat m) {
  final hist = Uint32List(256);
  final d = m.data;
  for (var i = 0; i < d.length; i++) {
    hist[d[i]]++;
  }
  // numpy.median semantics (mean of the two middle values for even counts)
  final n = d.length, lo = (n - 1) ~/ 2, hi = n ~/ 2;
  var acc = 0, vlo = -1, vhi = -1;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (vlo < 0 && acc > lo) vlo = v;
    if (acc > hi) {
      vhi = v;
      break;
    }
  }
  return (vlo + vhi) / 2;
}

cv.Mat _edgeMap(cv.Mat gray, bool equalize) {
  cv.Mat g;
  if (equalize) {
    final clahe = cv.CLAHE.create(_P.claheClip, (8, 8));
    g = clahe.apply(gray);
    clahe.dispose();
  } else {
    g = gray.clone();
  }
  final blurred = cv.gaussianBlur(g, (5, 5), 0);
  g.dispose();
  cv.Mat e;
  if (equalize) {
    e = cv.canny(blurred, _P.lowCanny[0].toDouble(), _P.lowCanny[1].toDouble());
  } else {
    final v = _median(blurred);
    final lo = math.max(math.max(0.0, 0.67 * v).truncate(), 10);
    final hi = math.max(math.min(255.0, 1.33 * v).truncate(), 30);
    e = cv.canny(blurred, lo.toDouble(), hi.toDouble());
  }
  blurred.dispose();
  final k = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
  final dilated = cv.dilate(e, k);
  k.dispose();
  e.dispose();
  return dilated;
}

List<Pt> _toPts(cv.VecPoint v) => [for (final p in v) Pt(p.x.toDouble(), p.y.toDouble())];

List<Pt> _approx(cv.VecPoint c, double eps) {
  final a = cv.approxPolyDP(c, eps, true);
  final pts = _toPts(a);
  a.dispose();
  return pts;
}

List<Pt>? _validate(List<Pt> contour, double cArea, List<Pt> q, double imgArea) {
  q = orderCorners(q);
  if (!isConvex(q)) return null;
  final qArea = polygonArea(q);
  if (qArea < _P.minAreaRatio * imgArea || cArea / qArea < _P.minFillRatio) return null;
  final ang = interiorAngles(q);
  if (ang.reduce(math.min) < _P.minAngle || ang.reduce(math.max) > _P.maxAngle) return null;
  final diag = q[2].distanceTo(q[0]);
  if (edgeDeviation(contour, q) > _P.maxEdgeDeviation * diag) return null;
  return q;
}

(List<Pt>, double)? _bestQuad(cv.Mat edges) {
  final imgArea = (edges.cols * edges.rows).toDouble();
  final (contours, hierarchy) = cv.findContours(edges, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
  final items = [for (final c in contours) (c, cv.contourArea(c))]..sort((a, b) => b.$2.compareTo(a.$2));
  List<Pt>? best;
  var bestArea = 0.0;
  for (final (c, area) in items.take(12)) {
    if (area < _P.minAreaRatio * imgArea * _P.minFillRatio) break;
    final peri = cv.arcLength(c, true);
    final candidates = <List<Pt>>[];
    for (final eps in _P.approxEpsilons) {
      final a = _approx(c, eps * peri);
      if (a.length == 4 && isConvex(a)) {
        candidates.add(a);
        break;
      }
    }
    final clipped = quadFromLongSides(_approx(c, _P.approxEpsilons.first * peri));
    if (clipped != null) candidates.add(clipped);
    final pts = _toPts(c);
    for (final cand in candidates) {
      final q = _validate(pts, area, cand, imgArea);
      if (q != null && polygonArea(q) > bestArea) {
        best = q;
        bestArea = polygonArea(q);
      }
    }
  }
  contours.dispose();
  hierarchy.dispose();
  return best == null ? null : (best, bestArea / imgArea);
}

Float32List _floatData(cv.Mat m) => m.data.buffer.asFloat32List(m.data.offsetInBytes, m.rows * m.cols);

/// Sharpen a rough quad to sub-pixel accuracy (see detect.py refine_corners).
List<Pt> _refineCorners(List<Pt> quad, cv.Mat gray) {
  final blurred = cv.gaussianBlur(gray, (5, 5), 0);
  final g = blurred.convertTo(cv.MatType.CV_32FC1);
  blurred.dispose();
  final gxm = cv.sobel(g, cv.MatType.CV_32F, 1, 0), gym = cv.sobel(g, cv.MatType.CV_32F, 0, 1);
  final w = g.cols, h = g.rows, gx = _floatData(gxm), gy = _floatData(gym);
  var q = [...quad];
  for (final band in _P.refineBands) {
    final lines = <(Pt, Pt)>[];
    for (var i = 0; i < 4; i++) {
      final a = q[i], ab = q[(i + 1) % 4] - a;
      final length = ab.length;
      final n = Pt(-ab.y / (length + 1e-6), ab.x / (length + 1e-6));
      final samples = math.max(12, length ~/ 3);
      final peaks = <Pt>[];
      for (var s = 0; s < samples; s++) {
        final base = a + ab * (0.1 + 0.8 * s / (samples - 1));
        var bestK = -1;
        var bestR = -1.0;
        for (var k = 0; k <= 2 * band; k++) {
          final o = (k - band).toDouble();
          final x = (base.x + o * n.x).round().clamp(0, w - 1), y = (base.y + o * n.y).round().clamp(0, h - 1);
          final r = (gx[y * w + x] * n.x + gy[y * w + x] * n.y).abs();
          if (r > bestR) {
            bestR = r;
            bestK = k;
          }
        }
        if (bestR > _P.refineMinGrad && bestK > 0 && bestK < 2 * band) {
          peaks.add(base + n * (bestK - band).toDouble());
        }
      }
      if (peaks.length >= 0.4 * samples) {
        final (c, dir) = fitLineHuber(peaks);
        lines.add((c, c + dir));
      } else {
        lines.add((a, a + ab));
      }
    }
    q = [
      for (var i = 0; i < 4; i++)
        () {
          final (p1, p2) = lines[(i + 3) % 4];
          final (p3, p4) = lines[i];
          final x = lineIntersection(p1, p2, p3, p4);
          return x == null || x.distanceTo(q[i]) > 3 * band ? q[i] : x;
        }(),
    ];
  }
  for (final m in [g, gxm, gym]) {
    m.dispose();
  }
  return q;
}

/// Size of the flattened page: the longer of each pair of opposite edges.
(int, int) outputSize(List<Pt> corners) {
  final c = orderCorners(corners);
  final w = math.max(c[1].distanceTo(c[0]), c[2].distanceTo(c[3]));
  final h = math.max(c[3].distanceTo(c[0]), c[2].distanceTo(c[1]));
  return (math.max(1, w.round()), math.max(1, h.round()));
}

/// Flatten the quad [corners] (any order) from [image] to a rectangle.
cv.Mat warpPerspectiveMat(cv.Mat image, List<Pt> corners, {int? maxSide}) {
  final src = orderCorners(corners);
  var (w, h) = outputSize(src);
  if (maxSide != null && math.max(w, h) > maxSide) {
    final s = maxSide / math.max(w, h);
    (w, h) = (math.max(1, (w * s).round()), math.max(1, (h * s).round()));
  }
  final sv = cv.VecPoint2f.fromList([for (final p in src) cv.Point2f(p.x, p.y)]);
  final dv = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(w - 1.0, 0),
    cv.Point2f(w - 1.0, h - 1.0),
    cv.Point2f(0, h - 1.0),
  ]);
  final m = cv.getPerspectiveTransform2f(sv, dv);
  final out = cv.warpPerspective(image, m, (w, h), flags: cv.INTER_CUBIC, borderMode: cv.BORDER_REPLICATE);
  sv.dispose();
  dv.dispose();
  m.dispose();
  return out;
}
