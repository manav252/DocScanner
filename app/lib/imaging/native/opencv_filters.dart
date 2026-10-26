// Enhancement filters + rotate/crop on Android/iOS (port of scanner_core/filters.py).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../page_edits.dart';

/// Paper/illumination level per pixel with the ink removed, estimated at low resolution.
cv.Mat _background(cv.Mat channel) {
  final w = channel.cols, h = channel.rows;
  final s = math.min(1.0, 400 / math.max(h, w));
  final small = cv.resize(channel, (
    math.max(1, (w * s).round()),
    math.max(1, (h * s).round()),
  ), interpolation: cv.INTER_AREA);
  final k = math.max(3, (math.min(small.rows, small.cols) ~/ 40) | 1);
  final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k));
  final dilated = cv.dilate(small, kernel);
  final median = cv.medianBlur(dilated, k * 2 + 1);
  final blurred = cv.gaussianBlur(median, (0, 0), k / 4);
  final bg = cv.resize(blurred, (w, h), interpolation: cv.INTER_LINEAR);
  for (final m in [small, kernel, dilated, median, blurred]) {
    m.dispose();
  }
  return bg;
}

/// Divide each channel by its background so the paper becomes evenly white.
cv.Mat removeShadows(cv.Mat image) {
  if (image.channels == 1) return _divideByBackground(image);
  final chans = cv.split(image);
  final out = cv.VecMat.fromList([for (final c in chans) _divideByBackground(c)]);
  final merged = cv.merge(out);
  chans.dispose();
  out.dispose();
  return merged;
}

cv.Mat _divideByBackground(cv.Mat c) {
  final bg = _background(c);
  final out = cv.divide(c, bg, scale: 255);
  bg.dispose();
  return out;
}

cv.Mat grayscale(cv.Mat image) => image.channels == 1 ? image.clone() : cv.cvtColor(image, cv.COLOR_BGR2GRAY);

cv.Mat blackAndWhite(cv.Mat image) {
  final g = grayscale(image);
  final flat = removeShadows(g);
  g.dispose();
  final block = math.max(15, (math.min(flat.rows, flat.cols) ~/ 30) | 1);
  final out = cv.adaptiveThreshold(flat, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 15);
  flat.dispose();
  // The outermost pixels often hold a sliver of desk/page edge: clear them.
  final m = math.max(2, (0.004 * math.min(out.rows, out.cols)).round());
  final d = out.data, w = out.cols, h = out.rows;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    if (y < m || y >= h - m) {
      d.fillRange(row, row + w, 255);
    } else {
      d.fillRange(row, row + m, 255);
      d.fillRange(row + w - m, row + w, 255);
    }
  }
  return out;
}

final Uint8List _magicLut = Uint8List.fromList([
  for (var v = 0; v < 256; v++) ((v - 20) * 255 / 215).clamp(0, 255).floor(),
]);

/// Shadow removal + local contrast + a little saturation ("Magic Color").
cv.Mat magicColor(cv.Mat image) {
  final bgr = image.channels == 1 ? cv.cvtColor(image, cv.COLOR_GRAY2BGR) : image.clone();
  final flat = removeShadows(bgr);
  bgr.dispose();
  final lab = cv.cvtColor(flat, cv.COLOR_BGR2Lab);
  flat.dispose();
  final ch = cv.split(lab);
  lab.dispose();
  final clahe = cv.CLAHE.create(1.5, (8, 8));
  final l1 = clahe.apply(ch[0]);
  clahe.dispose();
  final lut = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, _magicLut);
  final l2 = cv.LUT(l1, lut);
  final labOut = cv.merge(cv.VecMat.fromList([l2, ch[1], ch[2]]));
  final bgrOut = cv.cvtColor(labOut, cv.COLOR_Lab2BGR);
  final hsv = cv.split(cv.cvtColor(bgrOut, cv.COLOR_BGR2HSV));
  final sat = hsv[1].convertTo(cv.MatType.CV_8UC1, alpha: 1.25);
  final hsvOut = cv.merge(cv.VecMat.fromList([hsv[0], sat, hsv[2]]));
  final out = cv.cvtColor(hsvOut, cv.COLOR_HSV2BGR);
  for (final m in [l1, lut, l2, labOut, bgrOut, sat, hsvOut]) {
    m.dispose();
  }
  ch.dispose();
  hsv.dispose();
  return out;
}

cv.Mat applyFilter(cv.Mat image, PageFilter f) => switch (f) {
  PageFilter.original => image.clone(),
  PageFilter.grayscale => grayscale(image),
  PageFilter.bw => blackAndWhite(image),
  PageFilter.magicColor => magicColor(image),
};

cv.Mat rotateQuarterTurns(cv.Mat image, int turns) => switch (turns % 4) {
  1 => cv.rotate(image, cv.ROTATE_90_CLOCKWISE),
  2 => cv.rotate(image, cv.ROTATE_180),
  3 => cv.rotate(image, cv.ROTATE_90_COUNTERCLOCKWISE),
  _ => image.clone(),
};

cv.Mat cropNormalized(cv.Mat image, CropRect r) {
  if (r.isFull) return image.clone();
  final w = image.cols, h = image.rows;
  final x0 = (r.left * w).round().clamp(0, w - 1), y0 = (r.top * h).round().clamp(0, h - 1);
  final x1 = ((r.left + r.width) * w).round().clamp(x0 + 1, w), y1 = ((r.top + r.height) * h).round().clamp(y0 + 1, h);
  return image.region(cv.Rect(x0, y0, x1 - x0, y1 - y0)).clone();
}

/// filter -> rotate -> crop, optionally downscaled so the longest side is <= [maxSide].
/// Text recognition input: enlarged so the long side is at least
/// [ocrMinSide] (at most [ocrMaxUpscale]x: ~30 px text on an ID card far from
/// the camera), capped at [ocrMaxSide]; [contrast]: grayscale + CLAHE.
/// Mirrors prepareOcr in web/opencv/scanner.js.
const ocrMinSide = 2000, ocrMaxSide = 2400, ocrMaxUpscale = 3.0, ocrClaheClip = 2.0;

cv.Mat prepareOcr(cv.Mat image, {bool contrast = false}) {
  final w = image.cols, h = image.rows, long = math.max(w, h);
  final s = long < ocrMinSide
      ? math.min(ocrMaxUpscale, ocrMinSide / long)
      : long > ocrMaxSide
      ? ocrMaxSide / long
      : 1.0;
  final sized = s == 1
      ? image.clone()
      : cv.resize(image, ((w * s).round(), (h * s).round()), interpolation: s > 1 ? cv.INTER_CUBIC : cv.INTER_AREA);
  if (!contrast) return sized;
  final gray = sized.channels == 1 ? sized.clone() : cv.cvtColor(sized, cv.COLOR_BGR2GRAY);
  sized.dispose();
  final clahe = cv.CLAHE.create(ocrClaheClip, (8, 8));
  final out = clahe.apply(gray);
  clahe.dispose();
  gray.dispose();
  return out;
}

cv.Mat applyEdits(cv.Mat flat, PageEdits e, {int? maxSide}) {
  var src = flat;
  cv.Mat? scaled;
  if (maxSide != null && math.max(flat.rows, flat.cols) > maxSide) {
    final s = maxSide / math.max(flat.rows, flat.cols);
    src = scaled = cv.resize(flat, ((flat.cols * s).round(), (flat.rows * s).round()), interpolation: cv.INTER_AREA);
  }
  final filtered = applyFilter(src, e.filter);
  scaled?.dispose();
  final rotated = rotateQuarterTurns(filtered, e.quarterTurns);
  filtered.dispose();
  final cropped = cropNormalized(rotated, e.crop);
  rotated.dispose();
  return cropped;
}
