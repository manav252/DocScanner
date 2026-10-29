// Document detection + perspective warp on Android/iOS via opencv_dart (FFI).
//
// A line-for-line port of scanner_core/detect.py (the reference) and of
// web/opencv/scanner.js:
//   downscale -> blur -> Canny -> dilate -> contours and long straight edges
//   -> candidate quads (4-point approximation, long sides, extreme points,
//      pairs of straight edges) -> best score (quad_scoring.dart)
//   -> refine each side: strongest-gradient search + robust line fit
// Passes: grayscale; CLAHE; lighting normalised + CLAHE; colour saturation.
// Later passes run unless an earlier one is confident. Full-frame fallback
// when nothing qualifies.
//
// All functions are synchronous and allocation-bounded so they can run on a
// background isolate for every preview frame.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../detector_params.dart';
import '../geometry.dart';
import '../page_curves.dart';
import '../quad_scoring.dart';

typedef _P = DetectorParams;

/// Detect the page in a BGR, BGRA or grayscale [image]. Corners are in source pixels.
Detection detectDocumentMat(cv.Mat image, {int maxDim = _P.maxDim}) {
  final w = image.cols, h = image.rows;
  if (w == 0 || h == 0) throw ArgumentError('empty image');
  final scale = math.min(1.0, maxDim / math.max(w, h));
  final small = scale < 1
      ? cv.resize(image, ((w * scale).round(), (h * scale).round()), interpolation: cv.INTER_AREA)
      : image.clone();
  const pad = _P.pad;
  final padded = cv.copyMakeBorder(small, pad, pad, pad, pad, cv.BORDER_REPLICATE);
  small.dispose();
  final gray = switch (padded.channels) {
    1 => padded.clone(),
    3 => cv.cvtColor(padded, cv.COLOR_BGR2GRAY),
    4 => cv.cvtColor(padded, cv.COLOR_BGRA2GRAY),
    final n => throw ArgumentError('unsupported channel count $n'),
  };
  final bgr = switch (padded.channels) {
    1 => null,
    3 => padded.clone(),
    _ => cv.cvtColor(padded, cv.COLOR_BGRA2BGR),
  };
  // Colour saturation: a page on a coloured background of the same brightness.
  cv.Mat? saturation() {
    if (bgr == null) return null;
    final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
    final parts = cv.split(hsv);
    hsv.dispose();
    parts[0].dispose();
    parts[2].dispose();
    return parts[1];
  }

  try {
    return _detectPadded(gray, saturation, bgr == null ? null : () => _paperMask(bgr), w, h, scale);
  } finally {
    gray.dispose();
    padded.dispose();
    bgr?.dispose();
  }
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

Detection _detectPadded(
  cv.Mat gray,
  cv.Mat? Function() saturation,
  cv.Mat Function()? paperMask,
  int w,
  int h,
  double scale,
) {
  const pad = _P.pad;
  // (channel, low thresholds, borders checked on the grayscale image instead of the channel)
  final passes = <(cv.Mat? Function(), bool, bool)>[
    (() => gray.clone(), false, false),
    (() => _clahe(gray), true, false),
    (() => _normalizeLighting(gray), true, false),
    // Lighting divided out, without CLAHE (whose builds differ by a grey level
    // here and there between OpenCV versions).
    (
      () {
        final clipped = _clipGlare(gray), flat = _flatten(clipped);
        clipped.dispose();
        final out = _suppressTexture(flat);
        flat.dispose();
        return out;
      },
      true,
      false,
    ),
    (saturation, false, false),
    // The paper mask: its outlines are checked against the photo's own edges
    // (the mask's are always crisp), so a blob of paper plus pale cloth does not pass.
    if (paperMask != null) (paperMask, false, true),
  ];
  ScoredQuad? best;
  for (final (make, low, onGray) in passes) {
    final channel = make(); // built only when needed
    if (channel == null) continue;
    final edges = _edgeMap(channel, low);
    final blurred = cv.gaussianBlur(onGray ? gray : channel, (5, 5), 0);
    final res = _bestQuad(edges, GrayImage(Uint8List.fromList(blurred.data), blurred.cols, blurred.rows));
    for (final m in [channel, edges, blurred]) {
      m.dispose();
    }
    if (res != null && (best == null || res.score > best.score)) best = res;
    if (best != null && best.score >= _P.confidentScore) break; // a clear page: skip the rest
  }
  if (best == null) return Detection(fullBounds(w, h), found: false);
  // Refining fits straight lines: wrong for a bowed side.
  final q = (best.curved ? best.quad : _refineCorners(best.quad, gray))
      .map(
        (p) => Pt(
          ((p.x - pad + 0.5) / scale - 0.5).clamp(0, w - 1).toDouble(),
          ((p.y - pad + 0.5) / scale - 0.5).clamp(0, h - 1).toDouble(),
        ),
      )
      .toList();
  return Detection(q, found: true, score: polygonArea(best.quad) / (gray.cols * gray.rows));
}

cv.Mat _clahe(cv.Mat gray) {
  final clahe = cv.CLAHE.create(_P.claheClip, (8, 8));
  final out = clahe.apply(gray);
  clahe.dispose();
  return out;
}

final _f32 = Float32List(1);

/// [v] rounded to float32, as numpy computes on float32 arrays.
double _toF32(double v) {
  _f32[0] = v;
  return _f32[0];
}

/// Divide by the lighting (two box blurs, about a Gaussian with sigma = long
/// side / 50; computed identically by every OpenCV version): shadows and
/// light falloff even out, local differences stay.
cv.Mat _flatten(cv.Mat channel) {
  final k = math.max(3, (math.max(channel.rows, channel.cols) ~/ 20) | 1);
  final b1 = cv.blur(channel, (k, k));
  final bg = cv.blur(b1, (k, k));
  b1.dispose();
  final g = channel.data, b = bg.data;
  final flat = Uint8List(g.length);
  for (var i = 0; i < g.length; i++) {
    flat[i] = _toF32(_toF32(g[i] / (b[i] + 1)) * 180).clamp(0, 255).toInt();
  }
  bg.dispose();
  return cv.Mat.fromList(channel.rows, channel.cols, cv.MatType.CV_8UC1, flat);
}

/// numpy.percentile (linear) of an 8-bit image.
double _percentile(cv.Mat m, double p) {
  final hist = Uint32List(256);
  final d = m.data;
  for (var i = 0; i < d.length; i++) {
    hist[d[i]]++;
  }
  final idx = p / 100 * (d.length - 1), lo = idx.floor(), hi = idx.ceil();
  int at(int k) {
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc > k) return v;
    }
    return 255;
  }

  final a = at(lo), b = at(hi);
  return a + (idx - lo) * (b - a);
}

/// Flash glare: brightness above the glarePercentile-th percentile cut to it,
/// so a burnt-out highlight does not outshine the page edge.
cv.Mat _clipGlare(cv.Mat gray) {
  final top = _percentile(gray, _P.glarePercentile).truncate(); // as numpy.uint8() does
  final d = Uint8List.fromList(gray.data);
  for (var i = 0; i < d.length; i++) {
    if (d[i] > top) d[i] = top;
  }
  return cv.Mat.fromList(gray.rows, gray.cols, cv.MatType.CV_8UC1, d);
}

/// Even out shadows, uneven light and glare: clip highlights, divide by the
/// lighting, then boost local contrast with CLAHE.
cv.Mat _normalizeLighting(cv.Mat gray) {
  final clipped = _clipGlare(gray), flat = _flatten(clipped);
  clipped.dispose();
  final out = _clahe(flat);
  flat.dispose();
  return out;
}

/// Page outline without what is on or under the page: a closing fills in dark
/// strokes (handwriting, ruled lines, print), a median blur flattens weave.
cv.Mat _suppressTexture(cv.Mat gray) {
  final k = math.max(3, (_P.textureMorph * math.max(gray.rows, gray.cols)).truncate() | 1);
  final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k));
  final closed = cv.morphologyEx(gray, cv.MORPH_CLOSE, kernel);
  kernel.dispose();
  final out = cv.medianBlur(closed, 5);
  closed.dispose();
  return out;
}

/// Where the paper is: colourless (saturation below paperSatMax) and bright
/// for its surroundings (brightness with the lighting divided out, above the
/// Otsu threshold); opened and closed to drop checks, rules and text; only the
/// largest region kept. 255 = paper. BGR in.
cv.Mat _paperMask(cv.Mat bgr) {
  final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
  final parts = cv.split(hsv);
  hsv.dispose();
  final val = _flatten(parts[2]);
  final (_, bright) = cv.threshold(val, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
  final s = parts[1].data, br = bright.data;
  final mask = Uint8List(s.length);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = s[i] < _P.paperSatMax && br[i] > 0 ? 255 : 0;
  }
  for (final m in [...parts, val, bright]) {
    m.dispose();
  }
  final k = math.max(3, (_P.paperMorph * math.max(bgr.rows, bgr.cols)).truncate() | 1);
  final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k));
  final raw = cv.Mat.fromList(bgr.rows, bgr.cols, cv.MatType.CV_8UC1, mask);
  final opened = cv.morphologyEx(raw, cv.MORPH_OPEN, kernel);
  final closed = cv.morphologyEx(opened, cv.MORPH_CLOSE, kernel);
  for (final m in [kernel, raw, opened]) {
    m.dispose();
  }
  final labels = cv.Mat.empty(), stats = cv.Mat.empty(), centroids = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(
    closed,
    labels,
    stats,
    centroids,
    8,
    cv.MatType.CV_32S,
    cv.CCL_DEFAULT,
  );
  var biggest = -1, area = -1;
  for (var i = 1; i < n; i++) {
    final a = stats.at<int>(i, cv.CC_STAT_AREA);
    if (a > area) {
      area = a;
      biggest = i;
    }
  }
  final l = labels.data.buffer.asInt32List(labels.data.offsetInBytes, labels.rows * labels.cols);
  final out = Uint8List(l.length);
  for (var i = 0; i < l.length; i++) {
    out[i] = biggest > 0 && l[i] == biggest ? 255 : 0;
  }
  for (final m in [closed, labels, stats, centroids]) {
    m.dispose();
  }
  return cv.Mat.fromList(bgr.rows, bgr.cols, cv.MatType.CV_8UC1, out);
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

/// Canny (thresholds from the median, or fixed low ones for flat images), then
/// close small gaps so a page border forms one closed outline.
cv.Mat _edgeMap(cv.Mat channel, bool low) {
  final blurred = cv.gaussianBlur(channel, (5, 5), 0);
  cv.Mat e;
  if (low) {
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

/// Best page outline in [edges]: candidates from the outlines (4-point
/// approximation, long sides, extreme points) and from long straight edges.
ScoredQuad? _bestQuad(cv.Mat edges, GrayImage img) {
  final imgArea = (edges.cols * edges.rows).toDouble();
  final (contours, hierarchy) = cv.findContours(edges, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
  final items = [for (final c in contours) (c, cv.contourArea(c))]..sort((a, b) => b.$2.compareTo(a.$2));
  ScoredQuad? best;
  void consider(ScoredQuad? r) {
    if (r != null && (best == null || r.score > best!.score)) best = r;
  }

  for (final (c, area) in items.take(12)) {
    if (area < _P.minAreaRatio * imgArea * _P.minFillRatio) break; // sorted: nothing further can qualify
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
    candidates.add(extremePoints(pts));
    for (final cand in candidates) {
      consider(scoreQuad(pts, area, cand, imgArea, img));
    }
  }
  // Straight edges: the long sides of the outlines, simplified. Pairs of them
  // recover corners hidden by fingers or merged with clutter. (Not
  // HoughLinesP: it is randomised and differs between OpenCV versions.)
  final minLen = _P.lineMinLength * math.max(edges.cols, edges.rows);
  final segments = <(double, double, double, double)>[];
  for (final (c, _) in items.take(12)) {
    final peri = cv.arcLength(c, true);
    if (peri < 2 * minLen) continue;
    final p = _approx(c, _P.lineEpsilon * peri);
    for (var k = 0; k < p.length; k++) {
      final a = p[k], b = p[(k + 1) % p.length];
      if (a.distanceTo(b) >= minLen) segments.add((a.x, a.y, b.x, b.y));
    }
  }
  contours.dispose();
  hierarchy.dispose();
  for (final q in lineQuads(segments, edges.cols, edges.rows)) {
    consider(scoreQuad(null, 0, q, imgArea, img));
  }
  return best;
}

Float32List _floatData(cv.Mat m) => m.data.buffer.asFloat32List(m.data.offsetInBytes, m.rows * m.cols);

/// Robust line fit with OpenCV's own DIST_HUBER (as the reference and the web
/// port use), so the refined corners come out the same.
(Pt, Pt) _fitLineHuber(List<Pt> pts) {
  final v = cv.VecPoint2f.fromList([for (final p in pts) cv.Point2f(p.x, p.y)]);
  final line = cv.fitLine2f(v, cv.DIST_HUBER, 0, 0.01, 0.01);
  final d = line.data.buffer.asFloat32List(line.data.offsetInBytes, 4);
  final out = (Pt(d[2].toDouble(), d[3].toDouble()), Pt(d[0].toDouble(), d[1].toDouble()));
  v.dispose();
  line.dispose();
  return out;
}

/// numpy.rint: halves round to the even neighbour (Dart's round() goes away from zero).
int _rint(double v) {
  final r = v.roundToDouble();
  return ((v - v.truncateToDouble()).abs() == 0.5 ? 2 * (v / 2).roundToDouble() : r).toInt();
}

/// Sharpen a rough quad to sub-pixel accuracy (see detect.py refine_corners).
List<Pt> _refineCorners(List<Pt> quad, cv.Mat gray) {
  final blurred = cv.gaussianBlur(gray, (5, 5), 0);
  final g = blurred.convertTo(cv.MatType.CV_32FC1);
  blurred.dispose();
  final gxm = cv.sobel(g, cv.MatType.CV_32F, 1, 0), gym = cv.sobel(g, cv.MatType.CV_32F, 0, 1);
  final w = g.cols, h = g.rows, gx = _floatData(gxm), gy = _floatData(gym), gv = _floatData(g);
  var q = [...quad];
  for (final band in _P.refineBands) {
    final lines = <(Pt, Pt)>[];
    for (var i = 0; i < 4; i++) {
      final a = q[i], ab = q[(i + 1) % 4] - a;
      final length = ab.length;
      final n = Pt(-ab.y / (length + 1e-6), ab.x / (length + 1e-6));
      final samples = math.max(12, length ~/ 3);
      // The border's direction: is the page brighter or darker than what is
      // outside it here? Only edges stepping the same way count, so an inner
      // box (a card's photo) or a shadow cannot capture the side.
      final centre = (q[0] + q[1] + q[2] + q[3]) * 0.25;
      final b = q[(i + 1) % 4];
      final outSign = (n.x * (a.x + b.x) + n.y * (a.y + b.y)) / 2 - (n.x * centre.x + n.y * centre.y) > 0 ? 1.0 : -1.0;
      double at(Pt p) => gv[_rint(p.y).clamp(0, h - 1) * w + _rint(p.x).clamp(0, w - 1)];
      final steps = [
        for (var s = 0; s < samples; s++)
          () {
            final base = a + ab * (0.1 + 0.8 * s / (samples - 1));
            final d = n * (_P.stepOffset * outSign);
            return at(base - d) - at(base + d);
          }(),
      ]..sort();
      final step = samples.isOdd ? steps[(samples - 1) ~/ 2] : (steps[samples ~/ 2 - 1] + steps[samples ~/ 2]) / 2;
      final want = step >= 0 ? -outSign : outSign; // sign of the gradient along n at the border
      final peaks = <Pt>[];
      for (var s = 0; s < samples; s++) {
        final base = a + ab * (0.1 + 0.8 * s / (samples - 1));
        var bestK = -1;
        var bestR = -1.0;
        for (var k = 0; k <= 2 * band; k++) {
          final o = (k - band).toDouble();
          final x = _rint(base.x + o * n.x).clamp(0, w - 1), y = _rint(base.y + o * n.y).clamp(0, h - 1);
          final r = math.max(0.0, want * (gx[y * w + x] * n.x + gy[y * w + x] * n.y));
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
        final (c, dir) = _fitLineHuber(peaks);
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

/// Top and bottom edge curves of the page at [corners] in [image] (BGR, BGRA
/// or gray), or null when both are straight (see page_curves in warp.py).
(List<double>, List<double>)? pageCurvesMat(cv.Mat image, List<Pt> corners) {
  final w = image.cols, h = image.rows;
  final s = math.min(1.0, curveWorkSide / math.max(w, h));
  final small = s < 1
      ? cv.resize(image, ((w * s).round(), (h * s).round()), interpolation: cv.INTER_AREA)
      : image.clone();
  final gray = switch (small.channels) {
    1 => small.clone(),
    3 => cv.cvtColor(small, cv.COLOR_BGR2GRAY),
    _ => cv.cvtColor(small, cv.COLOR_BGRA2GRAY),
  };
  small.dispose();
  final blurred = cv.gaussianBlur(gray, (5, 5), 0);
  gray.dispose();
  final img = GrayImage(Uint8List.fromList(blurred.data), blurred.cols, blurred.rows);
  blurred.dispose();
  return pageCurvesOn(img, s, corners);
}

/// Flatten the page: a grid warp following bowed top/bottom edges, or the
/// plain perspective warp when they are straight (see warp_page in warp.py).
cv.Mat warpPageMat(cv.Mat image, List<Pt> corners, {int? maxSide}) {
  final curves = pageCurvesMat(image, corners);
  if (curves == null) return warpPerspectiveMat(image, corners, maxSide: maxSide);
  final src = orderCorners(corners);
  var (w, h) = outputSize(src);
  if (maxSide != null && math.max(w, h) > maxSide) {
    final s = maxSide / math.max(w, h);
    (w, h) = (math.max(1, (w * s).round()), math.max(1, (h * s).round()));
  }
  final dv = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(w - 1.0, 0),
    cv.Point2f(w - 1.0, h - 1.0),
    cv.Point2f(0, h - 1.0),
  ]);
  final sv = cv.VecPoint2f.fromList([for (final p in src) cv.Point2f(p.x, p.y)]);
  final m = cv.getPerspectiveTransform2f(dv, sv); // output -> photo
  final k = [
    for (var r = 0; r < 3; r++)
      for (var c = 0; c < 3; c++) m.atF64(r, i1: c),
  ];
  sv.dispose();
  dv.dispose();
  m.dispose();
  Pt toPhoto(double u, double v) {
    final z = k[6] * u + k[7] * v + k[8];
    return Pt((k[0] * u + k[1] * v + k[2]) / z, (k[3] * u + k[4] * v + k[5]) / z);
  }

  const step = 8;
  final (mx, my, gw, gh) = gridMap(src, curves, w, h, toPhoto, step: step);
  cv.Mat full(Float32List grid) {
    final g = cv.Mat.fromList(gh, gw, cv.MatType.CV_32FC1, grid);
    final big = cv.resize(g, (gw * step, gh * step), interpolation: cv.INTER_LINEAR);
    final cropped = big.region(cv.Rect(0, 0, w, h)).clone();
    g.dispose();
    big.dispose();
    return cropped;
  }

  final mapX = full(mx), mapY = full(my);
  final out = cv.remap(image, mapX, mapY, cv.INTER_CUBIC, borderMode: cv.BORDER_REPLICATE);
  mapX.dispose();
  mapY.dispose();
  return out;
}
