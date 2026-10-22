/*
 * Document detection + perspective warp for the web build (opencv.js).
 *
 * A line-for-line port of scanner_core/detect.py, warp.py and filters.py:
 *   downscale -> grayscale -> blur -> Canny -> dilate -> contours
 *   -> largest convex 4-point polygon (approxPolyDP) -> order TL, TR, BR, BL
 *   -> refine each side: strongest-gradient search + robust line fit
 * Second pass with CLAHE + low Canny thresholds for low-contrast pages,
 * full-frame fallback when nothing qualifies.
 *
 * Works in a Web Worker (see scanner_worker.js) and in Node (tests).
 * Every function takes the initialised `cv` module as its first argument.
 * Images are RGBA {data: Uint8ClampedArray, width, height} (ImageData shape).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.DocScanner = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // Mirror of shared/detector_params.json (checked by tests).
  const PARAMS = {
    max_dim: 500,
    pad: 4,
    min_area_ratio: 0.08,
    min_fill_ratio: 0.85,
    max_edge_deviation: 0.025,
    min_angle: 35.0,
    max_angle: 145.0,
    approx_epsilons: [0.02, 0.03, 0.04],
    clahe_clip: 3.0,
    low_canny: [12, 36],
    refine_bands: [10, 5, 3],
    refine_min_grad: 20.0,
  };

  // ---------- pure geometry (no OpenCV) ----------

  function orderCorners(pts) {
    const cx = pts.reduce((s, p) => s + p[0], 0) / 4;
    const cy = pts.reduce((s, p) => s + p[1], 0) / 4;
    const sorted = pts
      .map((p) => [p[0], p[1]])
      .sort((a, b) => Math.atan2(a[1] - cy, a[0] - cx) - Math.atan2(b[1] - cy, b[0] - cx));
    let start = 0;
    for (let i = 1; i < 4; i++) {
      if (sorted[i][0] + sorted[i][1] < sorted[start][0] + sorted[start][1]) start = i;
    }
    return [0, 1, 2, 3].map((i) => sorted[(start + i) % 4]);
  }

  function fullBounds(w, h) {
    return [[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]];
  }

  function polyArea(q) {
    let a = 0;
    for (let i = 0; i < q.length; i++) {
      const p = q[i], n = q[(i + 1) % q.length];
      a += p[0] * n[1] - n[0] * p[1];
    }
    return Math.abs(a) / 2;
  }

  function isConvex(q) {
    let sign = 0;
    for (let i = 0; i < q.length; i++) {
      const a = q[i], b = q[(i + 1) % q.length], c = q[(i + 2) % q.length];
      const cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
      if (Math.abs(cr) < 1e-9) continue;
      if (sign === 0) sign = Math.sign(cr);
      else if (Math.sign(cr) !== sign) return false;
    }
    return sign !== 0;
  }

  function interiorAngles(q) {
    const out = [];
    for (let i = 0; i < 4; i++) {
      const a = q[(i + 3) % 4], b = q[i], c = q[(i + 1) % 4];
      const v1 = [a[0] - b[0], a[1] - b[1]], v2 = [c[0] - b[0], c[1] - b[1]];
      const cos = (v1[0] * v2[0] + v1[1] * v2[1]) / (Math.hypot(...v1) * Math.hypot(...v2) + 1e-6);
      out.push((Math.acos(Math.max(-1, Math.min(1, cos))) * 180) / Math.PI);
    }
    return out;
  }

  function percentile(arr, p) {
    const s = Float64Array.from(arr).sort();
    const idx = (p / 100) * (s.length - 1);
    const lo = Math.floor(idx), hi = Math.ceil(idx);
    return s[lo] + (s[hi] - s[lo]) * (idx - lo);
  }

  function edgeDeviation(contour, q) {
    const d = contour.map((p) => {
      let best = Infinity;
      for (let i = 0; i < 4; i++) {
        const a = q[i], b = q[(i + 1) % 4];
        const abx = b[0] - a[0], aby = b[1] - a[1];
        let t = ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / (abx * abx + aby * aby + 1e-6);
        t = Math.max(0, Math.min(1, t));
        best = Math.min(best, Math.hypot(p[0] - (a[0] + t * abx), p[1] - (a[1] + t * aby)));
      }
      return best;
    });
    return percentile(d, 90);
  }

  function lineIntersection(p1, p2, p3, p4) {
    const d = (p1[0] - p2[0]) * (p3[1] - p4[1]) - (p1[1] - p2[1]) * (p3[0] - p4[0]);
    if (Math.abs(d) < 1e-6) return null;
    const a = p1[0] * p2[1] - p1[1] * p2[0];
    const b = p3[0] * p4[1] - p3[1] * p4[0];
    return [(a * (p3[0] - p4[0]) - (p1[0] - p2[0]) * b) / d, (a * (p3[1] - p4[1]) - (p1[1] - p2[1]) * b) / d];
  }

  function quadFromLongSides(p) {
    const n = p.length;
    if (n < 5 || n > 8) return null;
    const len = p.map((a, i) => Math.hypot(p[(i + 1) % n][0] - a[0], p[(i + 1) % n][1] - a[1]));
    const keep = [...Array(n).keys()].sort((a, b) => len[b] - len[a]).slice(0, 4).sort((a, b) => a - b);
    const out = [];
    for (let k = 0; k < 4; k++) {
      const i = keep[k], j = keep[(k + 1) % 4];
      const x = lineIntersection(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]);
      if (!x) return null;
      out.push(x);
    }
    return out;
  }

  // ---------- OpenCV helpers ----------

  function matToPoints(m) {
    const d = m.data32S, out = [];
    for (let i = 0; i < d.length; i += 2) out.push([d[i], d[i + 1]]);
    return out;
  }

  function approx(cv, contour, eps) {
    const a = new cv.Mat();
    cv.approxPolyDP(contour, a, eps, true);
    const pts = matToPoints(a);
    a.delete();
    return pts;
  }

  function validate(cvContourPts, cArea, q, imgArea) {
    q = orderCorners(q);
    if (!isConvex(q)) return null;
    const qArea = polyArea(q);
    if (qArea < PARAMS.min_area_ratio * imgArea || cArea / qArea < PARAMS.min_fill_ratio) return null;
    const ang = interiorAngles(q);
    if (Math.min(...ang) < PARAMS.min_angle || Math.max(...ang) > PARAMS.max_angle) return null;
    const diag = Math.hypot(q[2][0] - q[0][0], q[2][1] - q[0][1]);
    if (edgeDeviation(cvContourPts, q) > PARAMS.max_edge_deviation * diag) return null;
    return q;
  }

  function bestQuad(cv, edges) {
    const imgArea = edges.cols * edges.rows;
    const contours = new cv.MatVector(), hier = new cv.Mat();
    cv.findContours(edges, contours, hier, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    const items = [];
    for (let i = 0; i < contours.size(); i++) {
      const c = contours.get(i);
      items.push({ c, area: cv.contourArea(c) });
    }
    items.sort((a, b) => b.area - a.area);
    let best = null, bestArea = 0;
    for (let k = 0; k < Math.min(12, items.length); k++) {
      const { c, area } = items[k];
      if (area < PARAMS.min_area_ratio * imgArea * PARAMS.min_fill_ratio) break;
      const peri = cv.arcLength(c, true);
      const candidates = [];
      for (const eps of PARAMS.approx_epsilons) {
        const a = approx(cv, c, eps * peri);
        if (a.length === 4 && isConvex(a)) { candidates.push(a); break; }
      }
      const clipped = quadFromLongSides(approx(cv, c, PARAMS.approx_epsilons[0] * peri));
      if (clipped) candidates.push(clipped);
      const pts = matToPoints(c);
      for (const cand of candidates) {
        const q = validate(pts, area, cand, imgArea);
        if (q && polyArea(q) > bestArea) { best = q; bestArea = polyArea(q); }
      }
    }
    items.forEach((it) => it.c.delete());
    contours.delete(); hier.delete();
    return best ? { quad: best, ratio: bestArea / imgArea } : null;
  }

  function edgeMap(cv, gray, equalize) {
    const g = new cv.Mat(), e = new cv.Mat();
    if (equalize) {
      const clahe = new cv.CLAHE(PARAMS.clahe_clip, new cv.Size(8, 8));
      clahe.apply(gray, g);
      clahe.delete();
    } else gray.copyTo(g);
    cv.GaussianBlur(g, g, new cv.Size(5, 5), 0);
    if (equalize) cv.Canny(g, e, PARAMS.low_canny[0], PARAMS.low_canny[1]);
    else {
      const v = median(g);
      cv.Canny(g, e, Math.max(Math.trunc(Math.max(0, 0.67 * v)), 10), Math.max(Math.trunc(Math.min(255, 1.33 * v)), 30));
    }
    const k = cv.getStructuringElement(cv.MORPH_RECT, new cv.Size(3, 3));
    cv.dilate(e, e, k);
    k.delete(); g.delete();
    return e;
  }

  function median(m) {
    const hist = new Uint32Array(256), d = m.data;
    for (let i = 0; i < d.length; i++) hist[d[i]]++;
    // numpy.median semantics (mean of the two middle values for even counts)
    const n = d.length, lo = Math.floor((n - 1) / 2), hi = Math.floor(n / 2);
    let acc = 0, vlo = -1, vhi = -1;
    for (let v = 0; v < 256; v++) {
      acc += hist[v];
      if (vlo < 0 && acc > lo) vlo = v;
      if (acc > hi) { vhi = v; break; }
    }
    return (vlo + vhi) / 2;
  }

  function fitLineHuber(cv, pts) {
    const m = cv.matFromArray(pts.length, 1, cv.CV_32FC2, pts.flat());
    const line = new cv.Mat();
    cv.fitLine(m, line, cv.DIST_HUBER, 0, 0.01, 0.01);
    const [vx, vy, x0, y0] = line.data32F;
    m.delete(); line.delete();
    return [[x0, y0], [x0 + vx, y0 + vy]];
  }

  function refineCorners(cv, quad, gray) {
    const g = new cv.Mat(), gx = new cv.Mat(), gy = new cv.Mat();
    cv.GaussianBlur(gray, g, new cv.Size(5, 5), 0);
    g.convertTo(g, cv.CV_32F);
    cv.Sobel(g, gx, cv.CV_32F, 1, 0, 3);
    cv.Sobel(g, gy, cv.CV_32F, 0, 1, 3);
    const w = g.cols, h = g.rows, GX = gx.data32F, GY = gy.data32F;
    let q = quad.map((p) => p.slice());
    for (const band of PARAMS.refine_bands) {
      const lines = [];
      for (let i = 0; i < 4; i++) {
        const a = q[i], b = q[(i + 1) % 4];
        const abx = b[0] - a[0], aby = b[1] - a[1];
        const length = Math.hypot(abx, aby);
        const nx = -aby / (length + 1e-6), ny = abx / (length + 1e-6);
        const S = Math.max(12, Math.trunc(length / 3));
        const peaks = [];
        for (let s = 0; s < S; s++) {
          const t = 0.1 + (0.8 * s) / (S - 1);
          const bx = a[0] + t * abx, by = a[1] + t * aby;
          let bestK = -1, bestR = -1;
          for (let k = 0; k <= 2 * band; k++) {
            const o = k - band;
            const x = Math.min(w - 1, Math.max(0, Math.round(bx + o * nx)));
            const y = Math.min(h - 1, Math.max(0, Math.round(by + o * ny)));
            const r = Math.abs(GX[y * w + x] * nx + GY[y * w + x] * ny);
            if (r > bestR) { bestR = r; bestK = k; }
          }
          if (bestR > PARAMS.refine_min_grad && bestK > 0 && bestK < 2 * band) {
            const o = bestK - band;
            peaks.push([bx + o * nx, by + o * ny]);
          }
        }
        lines.push(peaks.length >= 0.4 * S ? fitLineHuber(cv, peaks) : [a, b]);
      }
      q = [0, 1, 2, 3].map((i) => {
        const x = lineIntersection(...lines[(i + 3) % 4], ...lines[i]);
        return !x || Math.hypot(x[0] - q[i][0], x[1] - q[i][1]) > 3 * band ? q[i] : x;
      });
    }
    g.delete(); gx.delete(); gy.delete();
    return q;
  }

  /** Detect the page. Returns {corners: [[x,y] x4] TL,TR,BR,BL in source pixels, found, score}. */
  function detectDocument(cv, image, maxDim = PARAMS.max_dim) {
    const { width: w, height: h } = image;
    if (!w || !h) throw new Error('empty image');
    const src = cv.matFromImageData(image);
    const scale = Math.min(1, maxDim / Math.max(w, h));
    const small = new cv.Mat();
    if (scale < 1) cv.resize(src, small, new cv.Size(Math.round(w * scale), Math.round(h * scale)), 0, 0, cv.INTER_AREA);
    else src.copyTo(small);
    src.delete();
    const gray = new cv.Mat();
    cv.cvtColor(small, gray, cv.COLOR_RGBA2GRAY);
    small.delete();
    const pad = PARAMS.pad;
    cv.copyMakeBorder(gray, gray, pad, pad, pad, pad, cv.BORDER_REPLICATE);
    try {
      for (const equalize of [false, true]) {
        const e = edgeMap(cv, gray, equalize);
        const res = bestQuad(cv, e);
        e.delete();
        if (res) {
          const q = refineCorners(cv, res.quad, gray).map(([x, y]) => [
            Math.min(w - 1, Math.max(0, (x - pad + 0.5) / scale - 0.5)),
            Math.min(h - 1, Math.max(0, (y - pad + 0.5) / scale - 0.5)),
          ]);
          return { corners: q, found: true, score: res.ratio };
        }
      }
      return { corners: fullBounds(w, h), found: false, score: 0 };
    } finally {
      gray.delete();
    }
  }

  function outputSize(corners) {
    const [tl, tr, br, bl] = orderCorners(corners);
    const d = (p, q) => Math.hypot(p[0] - q[0], p[1] - q[1]);
    return [Math.max(1, Math.round(Math.max(d(tr, tl), d(br, bl)))), Math.max(1, Math.round(Math.max(d(bl, tl), d(br, tr))))];
  }

  /** Flatten the quad to a rectangle. Returns RGBA {data, width, height}. */
  function warpPerspective(cv, image, corners, maxSide) {
    const src = orderCorners(corners);
    let [w, h] = outputSize(src);
    if (maxSide && Math.max(w, h) > maxSide) {
      const s = maxSide / Math.max(w, h);
      w = Math.max(1, Math.round(w * s)); h = Math.max(1, Math.round(h * s));
    }
    const m = cv.matFromImageData(image);
    const sp = cv.matFromArray(4, 1, cv.CV_32FC2, src.flat());
    const dp = cv.matFromArray(4, 1, cv.CV_32FC2, [0, 0, w - 1, 0, w - 1, h - 1, 0, h - 1]);
    const M = cv.getPerspectiveTransform(sp, dp);
    const out = new cv.Mat();
    cv.warpPerspective(m, out, M, new cv.Size(w, h), cv.INTER_CUBIC, cv.BORDER_REPLICATE);
    const result = { data: new Uint8ClampedArray(out.data), width: w, height: h };
    [m, sp, dp, M, out].forEach((x) => x.delete());
    return result;
  }

  // ---------- filters (port of scanner_core/filters.py), applied to RGBA images ----------

  /** Paper/illumination level per pixel with the ink removed (1-channel Mat in, new Mat out). */
  function background(cv, ch) {
    const w = ch.cols, h = ch.rows;
    const s = Math.min(1, 400 / Math.max(h, w));
    const small = new cv.Mat();
    cv.resize(ch, small, new cv.Size(Math.max(1, Math.round(w * s)), Math.max(1, Math.round(h * s))), 0, 0, cv.INTER_AREA);
    const k = Math.max(3, Math.trunc(Math.min(small.rows, small.cols) / 40) | 1);
    const kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, new cv.Size(k, k));
    cv.dilate(small, small, kernel);
    cv.medianBlur(small, small, k * 2 + 1);
    cv.GaussianBlur(small, small, new cv.Size(0, 0), k / 4);
    const bg = new cv.Mat();
    cv.resize(small, bg, new cv.Size(w, h), 0, 0, cv.INTER_LINEAR);
    small.delete();
    kernel.delete();
    return bg;
  }

  /** Divide each channel by its background so the paper becomes evenly white. */
  function removeShadows(cv, m) {
    const chans = new cv.MatVector(), out = new cv.MatVector();
    cv.split(m, chans);
    for (let i = 0; i < chans.size(); i++) {
      const c = chans.get(i), bg = background(cv, c), d = new cv.Mat();
      cv.divide(c, bg, d, 255);
      out.push_back(d);
      [c, bg, d].forEach((x) => x.delete());
    }
    const res = new cv.Mat();
    cv.merge(out, res);
    chans.delete();
    out.delete();
    return res;
  }

  function blackAndWhite(cv, gray) {
    const flat = removeShadows(cv, gray), out = new cv.Mat();
    const block = Math.max(15, Math.trunc(Math.min(flat.rows, flat.cols) / 30) | 1);
    cv.adaptiveThreshold(flat, out, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 15);
    flat.delete();
    // The outermost pixels often hold a sliver of desk/page edge: clear them.
    const m = Math.max(2, Math.round(0.004 * Math.min(out.rows, out.cols)));
    const d = out.data, w = out.cols, h = out.rows;
    for (let y = 0; y < h; y++) {
      const row = y * w;
      if (y < m || y >= h - m) d.fill(255, row, row + w);
      else { d.fill(255, row, row + m); d.fill(255, row + w - m, row + w); }
    }
    return out;
  }

  const MAGIC_LUT = Array.from({ length: 256 }, (_, v) => Math.floor(Math.min(255, Math.max(0, ((v - 20) * 255) / 215))));

  /** Shadow removal + local contrast + a little saturation ("Magic Color"). RGB in, RGB out. */
  function magicColor(cv, rgb) {
    const flat = removeShadows(cv, rgb), lab = new cv.Mat();
    cv.cvtColor(flat, lab, cv.COLOR_RGB2Lab);
    flat.delete();
    const ch = new cv.MatVector();
    cv.split(lab, ch);
    const l = ch.get(0), l1 = new cv.Mat(), l2 = new cv.Mat();
    const clahe = new cv.CLAHE(1.5, new cv.Size(8, 8));
    clahe.apply(l, l1);
    clahe.delete();
    const lut = cv.matFromArray(1, 256, cv.CV_8UC1, MAGIC_LUT);
    cv.LUT(l1, lut, l2);
    ch.set(0, l2);
    cv.merge(ch, lab);
    const out = new cv.Mat(), hsv = new cv.Mat();
    cv.cvtColor(lab, out, cv.COLOR_Lab2RGB);
    cv.cvtColor(out, hsv, cv.COLOR_RGB2HSV);
    const hc = new cv.MatVector();
    cv.split(hsv, hc);
    const sat = hc.get(1);
    sat.convertTo(sat, -1, 1.25, 0);
    hc.set(1, sat);
    cv.merge(hc, hsv);
    cv.cvtColor(hsv, out, cv.COLOR_HSV2RGB);
    [lab, ch, l, l1, l2, lut, hsv, hc, sat].forEach((x) => x.delete());
    return out;
  }

  /** filter -> rotate -> crop, like scanner_core. image: RGBA ImageData-like. Returns RGBA. */
  function applyEdits(cv, image, edits, maxSide) {
    let src = cv.matFromImageData(image);
    if (maxSide && Math.max(src.rows, src.cols) > maxSide) {
      const s = maxSide / Math.max(src.rows, src.cols), r = new cv.Mat();
      cv.resize(src, r, new cv.Size(Math.round(src.cols * s), Math.round(src.rows * s)), 0, 0, cv.INTER_AREA);
      src.delete();
      src = r;
    }
    const rgb = new cv.Mat();
    cv.cvtColor(src, rgb, cv.COLOR_RGBA2RGB);
    src.delete();
    let out;
    switch (edits.filter) {
      case 'original':
        out = rgb.clone();
        break;
      case 'grayscale':
        out = new cv.Mat();
        cv.cvtColor(rgb, out, cv.COLOR_RGB2GRAY);
        break;
      case 'bw': {
        const g = new cv.Mat();
        cv.cvtColor(rgb, g, cv.COLOR_RGB2GRAY);
        out = blackAndWhite(cv, g);
        g.delete();
        break;
      }
      default:
        out = magicColor(cv, rgb);
    }
    rgb.delete();
    const turns = (((edits.turns || 0) % 4) + 4) % 4;
    if (turns) {
      const r = new cv.Mat();
      cv.rotate(out, r, [0, cv.ROTATE_90_CLOCKWISE, cv.ROTATE_180, cv.ROTATE_90_COUNTERCLOCKWISE][turns]);
      out.delete();
      out = r;
    }
    const [cl, ct, cw, chh] = edits.crop || [0, 0, 1, 1];
    if (!(cl <= 0.0005 && ct <= 0.0005 && cw >= 0.999 && chh >= 0.999)) {
      const W = out.cols, H = out.rows;
      const x0 = Math.min(W - 1, Math.max(0, Math.round(cl * W))), y0 = Math.min(H - 1, Math.max(0, Math.round(ct * H)));
      const x1 = Math.min(W, Math.max(x0 + 1, Math.round((cl + cw) * W))), y1 = Math.min(H, Math.max(y0 + 1, Math.round((ct + chh) * H)));
      const roi = out.roi(new cv.Rect(x0, y0, x1 - x0, y1 - y0)), c = roi.clone();
      roi.delete();
      out.delete();
      out = c;
    }
    const rgba = new cv.Mat();
    cv.cvtColor(out, rgba, out.channels() === 1 ? cv.COLOR_GRAY2RGBA : cv.COLOR_RGB2RGBA);
    out.delete();
    const result = { data: new Uint8ClampedArray(rgba.data), width: rgba.cols, height: rgba.rows };
    rgba.delete();
    return result;
  }

  return { PARAMS, detectDocument, warpPerspective, applyEdits, orderCorners, fullBounds, outputSize };
});
