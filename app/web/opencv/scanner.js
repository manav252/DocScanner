/*
 * Document detection + perspective warp for the web build (opencv.js).
 *
 * A line-for-line port of scanner_core/detect.py, warp.py and filters.py:
 *   downscale -> blur -> Canny -> dilate -> contours and long straight edges
 *   -> candidate quads (4-point approximation, long sides, extreme points,
 *      pairs of straight edges) -> best score (size, border support,
 *      squareness, outline fit) -> order TL, TR, BR, BL
 *   -> refine each side: strongest-gradient search + robust line fit
 * Passes: grayscale; CLAHE; lighting normalised + CLAHE; colour saturation.
 * Later passes run unless an earlier one is confident. Full-frame fallback
 * when nothing qualifies.
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
    min_area_ratio: 0.04,
    min_fill_ratio: 0.85,
    max_edge_deviation: 0.025,
    min_angle: 35.0,
    max_angle: 145.0,
    approx_epsilons: [0.02, 0.03, 0.04],
    clahe_clip: 3.0,
    low_canny: [12, 36],
    refine_bands: [10, 5, 3],
    refine_min_grad: 20.0,
    max_bow: 0.12,
    curved_bow: 0.02,
    min_support: 0.6,
    min_line_support: 0.75,
    step_offset: 3.0,
    step_min: 10.0,
    line_count: 8,
    confident_score: 0.35,
    line_min_length: 0.12,
    line_epsilon: 0.005,
    frame_margin: 0.012,
    max_frame_sides: 2,
    max_area: 0.95,
    frame_side_factor: 0.8,
    paper_sat_max: 60,
    paper_morph: 0.02,
    glare_percentile: 99.0,
    texture_morph: 0.02,
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

  // ---------- candidates and scoring (see quad_scoring.dart, detect.py) ----------

  /** Corners as the outline's most top-left/top-right/bottom-right/bottom-left points (curved pages too). */
  function extremePoints(c) {
    const pick = (f, max) => c.reduce((a, b) => ((max ? f(b) > f(a) : f(b) < f(a)) ? b : a));
    const sum = (p) => p[0] + p[1], diff = (p) => p[0] - p[1];
    return [pick(sum, false), pick(diff, true), pick(sum, true), pick(diff, false)];
  }

  /** Per side of q: [bow a in px along the left normal (0 = straight), 90th percentile residual]. */
  function sideFits(contour, q) {
    const p = [];
    for (let i = 0; i < contour.length; i++) {
      const a = contour[i], b = contour[(i + 1) % contour.length];
      const k = Math.max(1, Math.floor(Math.hypot(b[0] - a[0], b[1] - a[1]) / 2));
      for (let j = 0; j < k; j++) p.push([a[0] + ((b[0] - a[0]) * j) / k, a[1] + ((b[1] - a[1]) * j) / k]);
    }
    const T = [], D = [], dist = [];
    for (let i = 0; i < 4; i++) {
      const a = q[i], b = q[(i + 1) % 4];
      const abx = b[0] - a[0], aby = b[1] - a[1], L = Math.hypot(abx, aby) + 1e-6;
      const t = new Float64Array(p.length), d = new Float64Array(p.length), di = new Float64Array(p.length);
      for (let j = 0; j < p.length; j++) {
        const vx = p[j][0] - a[0], vy = p[j][1] - a[1];
        t[j] = (vx * abx + vy * aby) / L / L;
        d[j] = (vx * -aby + vy * abx) / L;
        di[j] = t[j] >= 0 && t[j] <= 1 ? Math.abs(d[j]) : Infinity;
      }
      T.push(t); D.push(d); dist.push(di);
    }
    const out = [];
    for (let i = 0; i < 4; i++) {
      const basis = [], dm = [];
      for (let j = 0; j < p.length; j++) {
        let side = 0;
        for (let k = 1; k < 4; k++) if (dist[k][j] < dist[side][j]) side = k;
        if (side === i && Number.isFinite(dist[i][j])) { basis.push(T[i][j] * (1 - T[i][j])); dm.push(D[i][j]); }
      }
      if (dm.length < 6) { out.push([0, 0]); continue; }
      const straight = percentile(dm.map(Math.abs), 90);
      const ratios = [];
      for (let j = 0; j < dm.length; j++) if (basis[j] > 0.1) ratios.push(dm[j] / basis[j]);
      if (ratios.length < 4) { out.push([0, straight]); continue; }
      const a = percentile(ratios, 50);
      const bowed = percentile(dm.map((d, j) => Math.abs(d - a * basis[j])), 90);
      out.push(straight <= 1.25 * bowed ? [0, straight] : [a, bowed]); // straight unless the curve fits clearly better
    }
    return out;
  }

  /** Share of each side (following its bow) with a consistent brightness step from inside to outside. */
  function edgeSupport(q, bows, img) {
    const { data, width: w, height: h } = img;
    const at = (x, y) => data[Math.min(h - 1, Math.max(0, Math.round(y))) * w + Math.min(w - 1, Math.max(0, Math.round(x)))];
    const cx = (q[0][0] + q[1][0] + q[2][0] + q[3][0]) / 4, cy = (q[0][1] + q[1][1] + q[2][1] + q[3][1]) / 4;
    const out = [];
    for (let i = 0; i < 4; i++) {
      const a = q[i], b = q[(i + 1) % 4];
      const abx = b[0] - a[0], aby = b[1] - a[1], L = Math.hypot(abx, aby) + 1e-6;
      const lx = -aby / L, ly = abx / L;
      const flip = lx * (cx - a[0]) + ly * (cy - a[1]) > 0 ? -1 : 1; // n points outwards
      const nx = lx * flip, ny = ly * flip;
      const d = [];
      for (let s = 0; s < 24; s++) {
        const t = 0.1 + (0.8 * s) / 23, bow = bows[i] * t * (1 - t);
        const bx = a[0] + t * abx + bow * lx, by = a[1] + t * aby + bow * ly;
        let best = 0;
        for (const o of [-1, 0, 1]) {
          const ki = o - PARAMS.step_offset, ko = o + PARAMS.step_offset;
          const diff = at(bx + ki * nx, by + ki * ny) - at(bx + ko * nx, by + ko * ny);
          if (Math.abs(diff) > Math.abs(best)) best = diff;
        }
        d.push(best);
      }
      const sign = percentile(d, 50) >= 0 ? 1 : -1;
      out.push(d.filter((v) => v * sign > PARAMS.step_min).length / 24);
    }
    return out;
  }

  /** {quad, score, curved} if q passes every check, else null. contour is null for a quad made of straight edges. */
  /** For each side of q: does it lie along the photo's border (both ends within frame_margin of the same edge of the unpadded photo)? */
  function onFrame(q, w, h) {
    const m = PARAMS.frame_margin * Math.max(w, h), pad = PARAMS.pad;
    const lo = pad + m, hx = w - 1 - pad - m, hy = h - 1 - pad - m;
    return [0, 1, 2, 3].map((i) => {
      const a = q[i], b = q[(i + 1) % 4];
      return (a[0] <= lo && b[0] <= lo) || (a[0] >= hx && b[0] >= hx) || (a[1] <= lo && b[1] <= lo) || (a[1] >= hy && b[1] >= hy);
    });
  }

  function scoreQuad(contour, cArea, q, imgArea, img) {
    q = orderCorners(q);
    if (!isConvex(q)) return null;
    const qArea = polyArea(q);
    if (qArea < PARAMS.min_area_ratio * imgArea || (contour && cArea / qArea < PARAMS.min_fill_ratio)) return null;
    // Never the photo itself (a checked cloth or the padding forms its border).
    const frameSides = onFrame(q, img.width, img.height).filter(Boolean).length;
    if (qArea > PARAMS.max_area * imgArea || frameSides > PARAMS.max_frame_sides) return null;
    const ang = interiorAngles(q);
    if (Math.min(...ang) < PARAMS.min_angle || Math.max(...ang) > PARAMS.max_angle) return null;
    let bows, minSupport, fit, bowRatio = 0;
    if (!contour) {
      bows = [0, 0, 0, 0]; minSupport = PARAMS.min_line_support; fit = 0.5;
    } else {
      const diag = Math.hypot(q[2][0] - q[0][0], q[2][1] - q[0][1]);
      const fits = sideFits(contour, q);
      bows = fits.map((f) => f[0]);
      for (let i = 0; i < 4; i++) {
        const L = Math.hypot(q[(i + 1) % 4][0] - q[i][0], q[(i + 1) % 4][1] - q[i][1]);
        bowRatio = Math.max(bowRatio, Math.abs(bows[i]) / 4 / L);
      }
      const resid = Math.max(...fits.map((f) => f[1]));
      if (resid > PARAMS.max_edge_deviation * diag || bowRatio > PARAMS.max_bow) return null;
      minSupport = PARAMS.min_support;
      fit = resid / (PARAMS.max_edge_deviation * diag);
    }
    const bowed = edgeSupport(q, bows, img), straight = edgeSupport(q, [0, 0, 0, 0], img);
    const support = bowed.map((v, i) => Math.max(v, straight[i]));
    if (Math.min(...support) < minSupport) return null;
    const squareness = 1 - ang.reduce((s, a) => s + Math.abs(a - 90), 0) / 4 / 90;
    // A side along the photo's border is less likely a page edge than the
    // photo's own border meeting cloth: prefer outlines inside the photo.
    const score = Math.sqrt(qArea / imgArea) * (support.reduce((s, v) => s + v, 0) / 4) * squareness * (1 - 0.1 * fit) *
      PARAMS.frame_side_factor ** frameSides;
    return { quad: q, score, curved: !!contour && bowRatio > PARAMS.curved_bow };
  }

  /** Quads made of 4 long straight edges (two roughly opposite pairs), extended to meet. */
  function lineQuads(segments, w, h) {
    const len = (s) => Math.hypot(s[2] - s[0], s[3] - s[1]);
    const segs = [...segments].sort((a, b) => len(b) - len(a));
    const lines = [];
    for (const [x1, y1, x2, y2] of segs) {
      const L = Math.hypot(x2 - x1, y2 - y1) + 1e-6;
      const dx = (x2 - x1) / L, dy = (y2 - y1) / L;
      const ang = (((Math.atan2(dy, dx) * 180) / Math.PI) % 180 + 180) % 180;
      const dup = lines.some((l) => {
        const da = Math.abs(ang - l.ang);
        return Math.min(da, 180 - da) < 8 && Math.abs(l.dx * (y1 - l.y) - l.dy * (x1 - l.x)) < 6;
      });
      if (dup) continue;
      lines.push({ x: x1, y: y1, dx, dy, ang });
      if (lines.length === PARAMS.line_count) break;
    }
    const horiz = lines.filter((l) => l.ang < 45 || l.ang >= 135), vert = lines.filter((l) => l.ang >= 45 && l.ang < 135);
    const quads = [];
    for (let i = 0; i < horiz.length; i++) for (let j = i + 1; j < horiz.length; j++)
      for (let k = 0; k < vert.length; k++) for (let m = k + 1; m < vert.length; m++) {
        const pts = [];
        for (const [a, b] of [[horiz[i], vert[k]], [vert[k], horiz[j]], [horiz[j], vert[m]], [vert[m], horiz[i]]]) {
          const x = lineIntersection([a.x, a.y], [a.x + a.dx, a.y + a.dy], [b.x, b.y], [b.x + b.dx, b.y + b.dy]);
          if (!x) break;
          pts.push(x);
        }
        if (pts.length === 4 && pts.every(([x, y]) => x > -0.02 * w && x < 1.02 * w && y > -0.02 * h && y < 1.02 * h)) quads.push(pts);
      }
    return quads;
  }

  /** Best page outline: {quad, score, curved, ratio} or null. img = the pass's blurred channel. */
  function bestQuad(cv, edges, img, log) {
    const imgArea = edges.cols * edges.rows;
    const contours = new cv.MatVector(), hier = new cv.Mat();
    cv.findContours(edges, contours, hier, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    const items = [];
    for (let i = 0; i < contours.size(); i++) {
      const c = contours.get(i);
      items.push({ c, area: cv.contourArea(c) });
    }
    items.sort((a, b) => b.area - a.area);
    let best = null;
    const consider = (r, q, kind) => {
      if (log) log.push({ kind, q, r });
      if (r && (!best || r.score > best.score)) best = r;
    };
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
      candidates.push(extremePoints(pts));
      for (const cand of candidates) consider(scoreQuad(pts, area, cand, imgArea, img), cand, 'contour');
    }
    // Straight edges: the long sides of the outlines, simplified. Pairs of them recover
    // corners hidden by fingers or merged with clutter. (Not HoughLinesP: it is
    // randomised and differs between OpenCV versions.)
    const minLen = PARAMS.line_min_length * Math.max(edges.cols, edges.rows);
    const segs = [];
    for (let k = 0; k < Math.min(12, items.length); k++) {
      const peri = cv.arcLength(items[k].c, true);
      if (peri < 2 * minLen) continue;
      const p = approx(cv, items[k].c, PARAMS.line_epsilon * peri);
      for (let i = 0; i < p.length; i++) {
        const a = p[i], b = p[(i + 1) % p.length];
        if (Math.hypot(b[0] - a[0], b[1] - a[1]) >= minLen) segs.push([a[0], a[1], b[0], b[1]]);
      }
    }
    items.forEach((it) => it.c.delete());
    contours.delete(); hier.delete();
    for (const q of lineQuads(segs, edges.cols, edges.rows)) consider(scoreQuad(null, 0, q, imgArea, img), q, 'line');
    if (best) best.ratio = polyArea(best.quad) / imgArea;
    return best;
  }

  /** Blur + Canny + dilate. Returns {blurred, edges} (caller deletes both). */
  function edgeSteps(cv, channel, low) {
    const g = new cv.Mat(), e = new cv.Mat();
    cv.GaussianBlur(channel, g, new cv.Size(5, 5), 0);
    if (low) cv.Canny(g, e, PARAMS.low_canny[0], PARAMS.low_canny[1]);
    else {
      const v = median(g);
      cv.Canny(g, e, Math.max(Math.trunc(Math.max(0, 0.67 * v)), 10), Math.max(Math.trunc(Math.min(255, 1.33 * v)), 30));
    }
    const k = cv.getStructuringElement(cv.MORPH_RECT, new cv.Size(3, 3));
    cv.dilate(e, e, k);
    k.delete();
    return { blurred: g, edges: e };
  }

  function clahe(cv, gray) {
    const out = new cv.Mat(), c = new cv.CLAHE(PARAMS.clahe_clip, new cv.Size(8, 8));
    c.apply(gray, out);
    c.delete();
    return out;
  }

  /** Divide by a heavily blurred copy (the lighting): shadows and light falloff even out. New Mat. */
  function flatten(cv, channel) {
    // Two box blurs (about a Gaussian with sigma = long side / 50): fast at any
    // size, and computed identically by every OpenCV version (Python, web, Dart).
    const k = Math.max(3, Math.floor(Math.max(channel.rows, channel.cols) / 20) | 1);
    const bg = new cv.Mat();
    cv.blur(channel, bg, new cv.Size(k, k));
    cv.blur(bg, bg, new cv.Size(k, k));
    const flat = new cv.Mat(channel.rows, channel.cols, cv.CV_8UC1);
    const g = channel.data, b = bg.data, f = flat.data;
    // In float32 steps, as numpy computes it.
    for (let i = 0; i < g.length; i++) f[i] = Math.min(255, Math.max(0, Math.trunc(Math.fround(Math.fround(g[i] / (b[i] + 1)) * 180))));
    bg.delete();
    return flat;
  }

  /** Flash glare: brightness above the glare_percentile-th percentile cut to it. New Mat. */
  function clipGlare(cv, gray) {
    const top = Math.trunc(percentile8(gray.data, PARAMS.glare_percentile)); // as numpy.uint8(numpy.percentile())
    const out = gray.clone(), d = out.data;
    for (let i = 0; i < d.length; i++) if (d[i] > top) d[i] = top;
    return out;
  }

  /** Even out shadows, uneven light and glare: clip highlights, divide by the lighting, then CLAHE. */
  function normalizeLighting(cv, gray) {
    const clipped = clipGlare(cv, gray);
    const flat = flatten(cv, clipped);
    clipped.delete();
    const out = clahe(cv, flat);
    flat.delete();
    return out;
  }

  /** Page outline without what is on or under it: closing fills in strokes and rules, median flattens weave. */
  function suppressTexture(cv, gray) {
    const k = Math.max(3, Math.trunc(PARAMS.texture_morph * Math.max(gray.rows, gray.cols)) | 1);
    const kernel = cv.getStructuringElement(cv.MORPH_RECT, new cv.Size(k, k));
    const closed = new cv.Mat(), out = new cv.Mat();
    cv.morphologyEx(gray, closed, cv.MORPH_CLOSE, kernel);
    cv.medianBlur(closed, out, 5);
    kernel.delete(); closed.delete();
    return out;
  }

  /**
   * Where the paper is: colourless (saturation below paper_sat_max) and bright
   * for its surroundings (brightness with the lighting divided out, above the
   * Otsu threshold); opened and closed to drop checks, rules and text; only
   * the largest region kept. 255 = paper. RGBA in.
   */
  function paperMask(cv, color) {
    const rgb = new cv.Mat(), hsv = new cv.Mat(), parts = new cv.MatVector();
    cv.cvtColor(color, rgb, cv.COLOR_RGBA2RGB);
    cv.cvtColor(rgb, hsv, cv.COLOR_RGB2HSV);
    cv.split(hsv, parts);
    const sat = parts.get(1), v = parts.get(2);
    const val = flatten(cv, v);
    const bright = new cv.Mat();
    cv.threshold(val, bright, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
    const mask = new cv.Mat(val.rows, val.cols, cv.CV_8UC1);
    const S = sat.data, B = bright.data, M = mask.data;
    for (let i = 0; i < M.length; i++) M[i] = S[i] < PARAMS.paper_sat_max && B[i] > 0 ? 255 : 0;
    rgb.delete(); hsv.delete(); sat.delete(); v.delete(); parts.delete(); val.delete(); bright.delete();
    const k = Math.max(3, Math.trunc(PARAMS.paper_morph * Math.max(mask.rows, mask.cols)) | 1);
    const kernel = cv.getStructuringElement(cv.MORPH_RECT, new cv.Size(k, k));
    cv.morphologyEx(mask, mask, cv.MORPH_OPEN, kernel);
    cv.morphologyEx(mask, mask, cv.MORPH_CLOSE, kernel);
    kernel.delete();
    const labels = new cv.Mat(), stats = new cv.Mat(), centroids = new cv.Mat();
    const n = cv.connectedComponentsWithStats(mask, labels, stats, centroids, 8, cv.CV_32S);
    let biggest = -1, area = -1;
    for (let i = 1; i < n; i++) {
      const a = stats.intAt(i, cv.CC_STAT_AREA);
      if (a > area) { area = a; biggest = i; }
    }
    const L = labels.data32S;
    for (let i = 0; i < M.length; i++) M[i] = biggest > 0 && L[i] === biggest ? 255 : 0;
    labels.delete(); stats.delete(); centroids.delete();
    return mask;
  }

  /**
   * The detection passes over a working image, in order: [name, make channel,
   * low thresholds, borders checked on the grayscale image instead of the channel].
   */
  function passes(cv, work) {
    return [
      ['normal', () => work.gray.clone(), false],
      ['low contrast (CLAHE)', () => clahe(cv, work.gray), true],
      ['shadows (lighting normalised)', () => normalizeLighting(cv, work.gray), true],
      ['texture suppressed', () => {
        // Lighting divided out, without CLAHE (whose opencv.js build differs
        // from native OpenCV by a grey level here and there).
        const clipped = clipGlare(cv, work.gray), flat = flatten(cv, clipped);
        const out = suppressTexture(cv, flat);
        clipped.delete(); flat.delete();
        return out;
      }, true],
      ['colour (saturation)', () => {
        const rgb = new cv.Mat(), hsv = new cv.Mat(), parts = new cv.MatVector();
        cv.cvtColor(work.color, rgb, cv.COLOR_RGBA2RGB);
        cv.cvtColor(rgb, hsv, cv.COLOR_RGB2HSV);
        cv.split(hsv, parts);
        const s = parts.get(1).clone();
        rgb.delete(); hsv.delete(); parts.delete();
        return s;
      }, false],
      // Its outlines are checked against the photo's own edges (the mask's are
      // always crisp), so a blob of paper plus pale cloth does not pass.
      ['paper (bright, colourless)', () => paperMask(cv, work.color), false, true],
    ];
  }

  /** Run the passes; best result {quad, score, curved, ratio, pass} or null. keep(steps) may keep the chosen pass's images. */
  function searchPasses(cv, work, keep) {
    let best = null;
    for (const [name, make, low, onGray] of passes(cv, work)) {
      const channel = make();
      const st = edgeSteps(cv, channel, low);
      if (onGray) {
        st.blurred.delete();
        st.blurred = new cv.Mat();
        cv.GaussianBlur(work.gray, st.blurred, new cv.Size(5, 5), 0);
      }
      const res = bestQuad(cv, st.edges, { data: st.blurred.data, width: st.blurred.cols, height: st.blurred.rows });
      channel.delete();
      if (res && (!best || res.score > best.score)) {
        best = { ...res, pass: name };
        if (keep) keep(st); else { st.blurred.delete(); st.edges.delete(); }
      } else { st.blurred.delete(); st.edges.delete(); }
      if (best && best.score >= PARAMS.confident_score) break; // a clear page: skip the rest
    }
    return best;
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
    const w = g.cols, h = g.rows, GX = gx.data32F, GY = gy.data32F, G = g.data32F;
    let q = quad.map((p) => p.slice());
    for (const band of PARAMS.refine_bands) {
      const lines = [];
      for (let i = 0; i < 4; i++) {
        const a = q[i], b = q[(i + 1) % 4];
        const abx = b[0] - a[0], aby = b[1] - a[1];
        const length = Math.hypot(abx, aby);
        const nx = -aby / (length + 1e-6), ny = abx / (length + 1e-6);
        const S = Math.max(12, Math.trunc(length / 3));
        // The border's direction: is the page brighter or darker than what is
        // outside it here? Only edges stepping the same way count, so an inner
        // box (a card's photo) or a shadow cannot capture the side.
        const cx = (q[0][0] + q[1][0] + q[2][0] + q[3][0]) / 4, cy = (q[0][1] + q[1][1] + q[2][1] + q[3][1]) / 4;
        const outSign = (nx * (a[0] + b[0]) + ny * (a[1] + b[1])) / 2 - (nx * cx + ny * cy) > 0 ? 1 : -1;
        const px = (v) => Math.min(w - 1, Math.max(0, Math.round(v))), py = (v) => Math.min(h - 1, Math.max(0, Math.round(v)));
        const steps = [];
        for (let s = 0; s < S; s++) {
          const t = 0.1 + (0.8 * s) / (S - 1);
          const bx = a[0] + t * abx, by = a[1] + t * aby, d = PARAMS.step_offset * outSign;
          steps.push(G[py(by - d * ny) * w + px(bx - d * nx)] - G[py(by + d * ny) * w + px(bx + d * nx)]);
        }
        steps.sort((u, v) => u - v);
        const step = S % 2 ? steps[(S - 1) / 2] : (steps[S / 2 - 1] + steps[S / 2]) / 2;
        const want = step >= 0 ? -outSign : outSign; // sign of the gradient along n at the border
        const peaks = [];
        for (let s = 0; s < S; s++) {
          const t = 0.1 + (0.8 * s) / (S - 1);
          const bx = a[0] + t * abx, by = a[1] + t * aby;
          let bestK = -1, bestR = -1;
          for (let k = 0; k <= 2 * band; k++) {
            const o = k - band;
            const x = Math.min(w - 1, Math.max(0, Math.round(bx + o * nx)));
            const y = Math.min(h - 1, Math.max(0, Math.round(by + o * ny)));
            const r = Math.max(0, want * (GX[y * w + x] * nx + GY[y * w + x] * ny));
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

  /** Downscaled, padded working images. Returns {gray, color (RGBA), scale} (caller deletes both). */
  function workingImage(cv, image, maxDim) {
    const { width: w, height: h } = image;
    if (!w || !h) throw new Error('empty image');
    const src = cv.matFromImageData(image);
    const scale = Math.min(1, maxDim / Math.max(w, h));
    const small = new cv.Mat();
    if (scale < 1) cv.resize(src, small, new cv.Size(Math.round(w * scale), Math.round(h * scale)), 0, 0, cv.INTER_AREA);
    else src.copyTo(small);
    src.delete();
    const pad = PARAMS.pad;
    const color = new cv.Mat();
    cv.copyMakeBorder(small, color, pad, pad, pad, pad, cv.BORDER_REPLICATE);
    small.delete();
    const gray = new cv.Mat();
    cv.cvtColor(color, gray, cv.COLOR_RGBA2GRAY);
    return { gray, color, scale };
  }

  /** Detect the page. Returns {corners: [[x,y] x4] TL,TR,BR,BL in source pixels, found, score}. */
  function detectDocument(cv, image, maxDim = PARAMS.max_dim) {
    const { width: w, height: h } = image;
    const work = workingImage(cv, image, maxDim);
    try {
      return finish(cv, searchPasses(cv, work), work, w, h);
    } finally {
      work.gray.delete(); work.color.delete();
    }
  }

  /** Map the chosen quad back to source pixels (refined unless a side bows). */
  function finish(cv, best, work, w, h) {
    if (!best) return { corners: fullBounds(w, h), found: false, score: 0 };
    const pad = PARAMS.pad, scale = work.scale;
    const q = (best.curved ? best.quad : refineCorners(cv, best.quad, work.gray)).map(([x, y]) => [
      Math.min(w - 1, Math.max(0, (x - pad + 0.5) / scale - 0.5)),
      Math.min(h - 1, Math.max(0, (y - pad + 0.5) / scale - 0.5)),
    ]);
    return { corners: q, found: true, score: best.ratio };
  }

  function outputSize(corners) {
    const [tl, tr, br, bl] = orderCorners(corners);
    const d = (p, q) => Math.hypot(p[0] - q[0], p[1] - q[1]);
    return [Math.max(1, Math.round(Math.max(d(tr, tl), d(br, bl)))), Math.max(1, Math.round(Math.max(d(bl, tl), d(br, tr))))];
  }

  /** Flatten the quad to a rectangle. Returns RGBA {data, width, height}. */
  // ---------- OCR input (see ocr_prep in opencv_filters.dart) ----------

  // iPhone/iPad: a smaller text recognition image (Tesseract's memory grows with
  // it; the page crashed during recognition on an iPhone).
  const IOS = typeof navigator !== 'undefined' &&
    (/iPhone|iPad|iPod/.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1));
  const OCR = IOS
    ? { minSide: 1600, maxSide: 1600, maxUpscale: 3, claheClip: 2.0 }
    : { minSide: 2000, maxSide: 2400, maxUpscale: 3, claheClip: 2.0 };

  /**
   * The page image prepared for text recognition: small pages (an ID card far
   * from the camera) are enlarged so their text is ~30 px tall or more, large
   * ones capped. variant 'contrast': grayscale + CLAHE (a second try when the
   * first finds little text).
   */
  function prepareOcr(cv, image, variant = 'main') {
    const { width: w, height: h } = image;
    const long = Math.max(w, h);
    const s = long < OCR.minSide ? Math.min(OCR.maxUpscale, OCR.minSide / long) : long > OCR.maxSide ? OCR.maxSide / long : 1;
    const src = cv.matFromImageData(image), out = new cv.Mat();
    if (s !== 1) {
      cv.resize(src, out, new cv.Size(Math.round(w * s), Math.round(h * s)), 0, 0, s > 1 ? cv.INTER_CUBIC : cv.INTER_AREA);
    } else src.copyTo(out);
    src.delete();
    if (variant === 'contrast') {
      const g = new cv.Mat(), c = new cv.CLAHE(OCR.claheClip, new cv.Size(8, 8));
      cv.cvtColor(out, g, cv.COLOR_RGBA2GRAY);
      c.apply(g, g);
      cv.cvtColor(g, out, cv.COLOR_GRAY2RGBA);
      g.delete(); c.delete();
    }
    const result = { data: new Uint8ClampedArray(out.data), width: out.cols, height: out.rows };
    out.delete();
    return result;
  }

  // ---------- curved pages (see page_curves.dart, warp.py) ----------

  const CURVE = { minBow: 0.015, maxBow: 0.15, samples: 48, workSide: 1000, minStep: 12.0 };

  /** d(t) = t(1-t)(c0 + c1 t): zero at both corners. */
  const curveAt = (c, t) => t * (1 - t) * (c[0] + c[1] * t);

  /** numpy.rint: halves round to the even neighbour. */
  function rint(v) {
    const f = Math.floor(v), d = v - f;
    return d === 0.5 ? (f % 2 === 0 ? f : f + 1) : Math.round(v);
  }

  /** numpy.arange(start, stop) for floats. */
  const arange = (a, b) => Array.from({ length: Math.max(0, Math.ceil(b - a)) }, (_, i) => a + i);

  const medianOf = (v) => {
    const s = [...v].sort((x, y) => x - y), n = s.length;
    return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
  };

  /** Trace the page edge between corners a and b and fit d(t); [0, 0] if straight or not traceable. */
  function sideCurve(g, a, b, out) {
    const step = (p) => {
      const at = (x, y) => g.data[Math.min(g.height - 1, Math.max(0, rint(y))) * g.width + Math.min(g.width - 1, Math.max(0, rint(x)))];
      return at(p[0] - 2 * out[0], p[1] - 2 * out[1]) - at(p[0] + 2 * out[0], p[1] + 2 * out[1]);
    };
    const L = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (L < 20) return [0, 0];
    const maxOff = CURVE.maxBow * L, window = Math.max(3, 0.02 * L);
    const ts = Array.from({ length: CURVE.samples }, (_, i) => 0.04 + ((0.96 - 0.04) * i) / (CURVE.samples - 1));
    const chord = ts.map((t) => [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]);
    const straight = chord.map(step);
    const near = arange(-window, window + 1);
    const ends = [...chord.slice(0, 4), ...chord.slice(-4)].map((base) => {
      let best = 0, first = true;
      for (const o of near) {
        const v = step([base[0] + o * out[0], base[1] + o * out[1]]);
        if (first || Math.abs(v) > Math.abs(best)) best = v;
        first = false;
      }
      return best;
    });
    const sign = medianOf(ends) >= 0 ? 1 : -1;
    let prev = 0;
    const T = [], D = [];
    for (let i = 0; i < ts.length; i++) {
      const offs = arange(Math.max(-maxOff, prev - window), Math.min(maxOff, prev + window) + 1);
      let k = -1, best = -Infinity;
      for (let j = 0; j < offs.length; j++) {
        const v = sign * step([chord[i][0] + offs[j] * out[0], chord[i][1] + offs[j] * out[1]]);
        if (v > best) { best = v; k = j; }
      }
      if (k >= 0 && best >= CURVE.minStep) { prev = offs[k]; T.push(ts[i]); D.push(prev); }
    }
    if (T.length < 0.7 * ts.length) return [0, 0];
    let keep = T.map(() => true), c = [0, 0];
    for (let it = 0; it < 3; it++) {
      let s11 = 0, s12 = 0, s22 = 0, r1 = 0, r2 = 0;
      for (let j = 0; j < T.length; j++) {
        if (!keep[j]) continue;
        const t = T[j], b1 = t * (1 - t), b2 = t * t * (1 - t);
        s11 += b1 * b1; s12 += b1 * b2; s22 += b2 * b2; r1 += b1 * D[j]; r2 += b2 * D[j];
      }
      const det = s11 * s22 - s12 * s12;
      if (Math.abs(det) < 1e-12) return [0, 0];
      c = [(r1 * s22 - r2 * s12) / det, (s11 * r2 - s12 * r1) / det];
      const res = T.map((t, j) => Math.abs(D[j] - curveAt(c, t)));
      const limit = Math.max(2, 2.5 * medianOf(res.filter((_, j) => keep[j])));
      keep = res.map((r) => r <= limit);
    }
    let onCurve = 0, onChord = 0;
    for (let i = 0; i < ts.length; i++) {
      const d = curveAt(c, ts[i]);
      if (sign * step([chord[i][0] + d * out[0], chord[i][1] + d * out[1]]) >= CURVE.minStep) onCurve++;
      if (sign * straight[i] >= CURVE.minStep) onChord++;
    }
    const fc = onCurve / ts.length, fs = onChord / ts.length;
    return fc < 0.8 || fc < fs + 0.15 ? [0, 0] : c;
  }

  function outwardNormal(a, b, centre) {
    const L = Math.hypot(b[0] - a[0], b[1] - a[1]) + 1e-9;
    let n = [-(b[1] - a[1]) / L, (b[0] - a[0]) / L];
    if (n[0] * (centre[0] - a[0]) + n[1] * (centre[1] - a[1]) > 0) n = [-n[0], -n[1]];
    return n;
  }

  /** Top and bottom edge curves (photo px) of the page at corners, or null when both are straight. */
  function pageCurves(cv, image, corners) {
    const { width: w, height: h } = image;
    const q = orderCorners(corners);
    const s = Math.min(1, CURVE.workSide / Math.max(w, h));
    const src = cv.matFromImageData(image), small = new cv.Mat(), gray = new cv.Mat();
    if (s < 1) cv.resize(src, small, new cv.Size(Math.round(w * s), Math.round(h * s)), 0, 0, cv.INTER_AREA);
    else src.copyTo(small);
    cv.cvtColor(small, gray, cv.COLOR_RGBA2GRAY);
    cv.GaussianBlur(gray, gray, new cv.Size(5, 5), 0);
    const g = { data: gray.data, width: gray.cols, height: gray.rows };
    const qs = q.map(([x, y]) => [x * s, y * s]);
    const centre = [(qs[0][0] + qs[1][0] + qs[2][0] + qs[3][0]) / 4, (qs[0][1] + qs[1][1] + qs[2][1] + qs[3][1]) / 4];
    const curves = [[0, 1], [3, 2]].map(([i, j]) => sideCurve(g, qs[i], qs[j], outwardNormal(qs[i], qs[j], centre)).map((v) => v / s));
    [src, small, gray].forEach((m) => m.delete());
    let bow = 0;
    [[0, 1], [3, 2]].forEach(([i, j], k) => {
      const L = Math.hypot(q[j][0] - q[i][0], q[j][1] - q[i][1]);
      for (let t = 0; t <= 100; t++) bow = Math.max(bow, Math.abs(curveAt(curves[k], t / 100)) / L);
    });
    return bow < CURVE.minBow ? null : curves;
  }

  /** Flatten the page: grid warp following bowed top/bottom edges, else the perspective warp. */
  function warpPage(cv, image, corners, maxSide) {
    const curves = pageCurves(cv, image, corners);
    if (!curves) return warpPerspective(cv, image, corners, maxSide);
    const src = orderCorners(corners);
    let [w, h] = outputSize(src);
    if (maxSide && Math.max(w, h) > maxSide) {
      const s = maxSide / Math.max(w, h);
      w = Math.max(1, Math.round(w * s)); h = Math.max(1, Math.round(h * s));
    }
    const dp = cv.matFromArray(4, 1, cv.CV_32FC2, [0, 0, w - 1, 0, w - 1, h - 1, 0, h - 1]);
    const sp = cv.matFromArray(4, 1, cv.CV_32FC2, src.flat());
    const M = cv.getPerspectiveTransform(dp, sp); // output -> photo
    const k = Array.from(M.data64F);
    [dp, sp, M].forEach((m) => m.delete());
    const toPhoto = (u, v) => {
      const z = k[6] * u + k[7] * v + k[8];
      return [(k[0] * u + k[1] * v + k[2]) / z, (k[3] * u + k[4] * v + k[5]) / z];
    };
    // The map on a coarse grid: point j stands for output pixel 8j + 3.5 (resizing aligns pixel centres).
    const step = 8, gw = Math.floor(w / step) + 2, gh = Math.floor(h / step) + 2;
    const U = Array.from({ length: gw }, (_, j) => j * step + (step - 1) / 2);
    const V = Array.from({ length: gh }, (_, i) => i * step + (step - 1) / 2);
    const centre = [(src[0][0] + src[1][0] + src[2][0] + src[3][0]) / 4, (src[0][1] + src[1][1] + src[2][1] + src[3][1]) / 4];
    const sides = [[curves[0], src[0], src[1], 0], [curves[1], src[3], src[2], h - 1]].map(([c, a, b, row]) => {
      const abx = b[0] - a[0], aby = b[1] - a[1], L2 = abx * abx + aby * aby;
      const d = U.map((u) => {
        const e = toPhoto(u, row);
        return curveAt(c, Math.min(1, Math.max(0, ((e[0] - a[0]) * abx + (e[1] - a[1]) * aby) / L2)));
      });
      return { n: outwardNormal(a, b, centre), d };
    });
    const mx = new Float32Array(gw * gh), my = new Float32Array(gw * gh);
    for (let i = 0; i < gh; i++) {
      const wt = 1 - V[i] / (h - 1), wb = V[i] / (h - 1);
      for (let j = 0; j < gw; j++) {
        const p = toPhoto(U[j], V[i]);
        mx[i * gw + j] = p[0] + sides[0].n[0] * wt * sides[0].d[j] + sides[1].n[0] * wb * sides[1].d[j];
        my[i * gw + j] = p[1] + sides[0].n[1] * wt * sides[0].d[j] + sides[1].n[1] * wb * sides[1].d[j];
      }
    }
    const full = (grid) => {
      const g = cv.matFromArray(gh, gw, cv.CV_32FC1, Array.from(grid)), big = new cv.Mat();
      cv.resize(g, big, new cv.Size(gw * step, gh * step), 0, 0, cv.INTER_LINEAR);
      const out = big.roi(new cv.Rect(0, 0, w, h)).clone();
      g.delete(); big.delete();
      return out;
    };
    const mapX = full(mx), mapY = full(my), m = cv.matFromImageData(image), out = new cv.Mat();
    cv.remap(m, out, mapX, mapY, cv.INTER_CUBIC, cv.BORDER_REPLICATE);
    const result = { data: new Uint8ClampedArray(out.data), width: w, height: h };
    [mapX, mapY, m, out].forEach((x) => x.delete());
    return result;
  }

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

  const PHOTO = { strip: 0.3, minTone: 0.2 };

  /** numpy.percentile (linear) of 8-bit data, from its histogram. */
  function percentile8(d, p) {
    const hist = new Uint32Array(256);
    for (let i = 0; i < d.length; i++) hist[d[i]]++;
    const idx = (p / 100) * (d.length - 1);
    const at = (k) => {
      let acc = 0;
      for (let v = 0; v < 256; v++) { acc += hist[v]; if (acc > k) return v; }
      return 255;
    };
    const lo = Math.floor(idx), hi = Math.ceil(idx);
    return at(lo) + (at(hi) - at(lo)) * (idx - lo);
  }

  /** ID card: [x, y, w, h] of the short-side strip with the photo (and PAN signature), or null. See filters.py. */
  function findPhotoStrip(gray) {
    const w = gray.cols, h = gray.rows, d = gray.data, bg = percentile8(d, 90);
    const share = ([x0, y0, sw, sh]) => {
      let n = 0;
      for (let y = y0; y < y0 + sh; y++) for (let x = x0; x < x0 + sw; x++) {
        const v = d[y * w + x];
        if (v < bg - 25 && v > 60) n++;
      }
      return n / (sw * sh);
    };
    let strips;
    if (w >= h) { const k = Math.trunc(PHOTO.strip * w); strips = [[0, 0, k, h], [w - k, 0, k, h]]; }
    else { const k = Math.trunc(PHOTO.strip * h); strips = [[0, 0, w, k], [0, h - k, w, k]]; }
    const a = share(strips[0]), b = share(strips[1]);
    const top = Math.max(a, b), other = a >= b ? b : a;
    return top >= PHOTO.minTone && top >= 1.5 * other ? (a >= b ? strips[0] : strips[1]) : null;
  }

  function blackAndWhite(cv, gray, keepPhoto = false) {
    const flat = removeShadows(cv, gray), out = new cv.Mat();
    const block = Math.max(15, Math.trunc(Math.min(flat.rows, flat.cols) / 30) | 1);
    cv.adaptiveThreshold(flat, out, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 15);
    flat.delete();
    // ID cards: the photo/signature strip keeps its grey tones (brightened so the card is white).
    const strip = keepPhoto ? findPhotoStrip(gray) : null;
    if (strip) {
      const bg = Math.max(1, percentile8(gray.data, 90)), [x0, y0, sw, sh] = strip, src = gray.data, dst = out.data, w = out.cols;
      for (let y = y0; y < y0 + sh; y++) for (let x = x0; x < x0 + sw; x++) {
        dst[y * w + x] = Math.min(255, Math.max(0, Math.trunc(src[y * w + x] * (255 / bg))));
      }
    }
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
        out = blackAndWhite(cv, g, !!edits.card);
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


  // ---------- "How it works": the same steps, with a picture of each ----------

  function grayToRGBA(cv, m) {
    const out = new cv.Mat();
    cv.cvtColor(m, out, cv.COLOR_GRAY2RGBA);
    const r = { data: new Uint8ClampedArray(out.data), width: out.cols, height: out.rows };
    out.delete();
    return r;
  }

  function rgbaFromMat(m) {
    return { data: new Uint8ClampedArray(m.data), width: m.cols, height: m.rows };
  }

  /**
   * Run detection step by step and return an image for each step:
   * gray, blurred, edges, contours (all outlines; the chosen page in green),
   * corners (on the photo), flattened (the warped page).
   * Uses the same functions as detectDocument; `result` is identical to it.
   */
  function explainDetection(cv, image, maxDim = PARAMS.max_dim) {
    const { width: w, height: h } = image;
    const work = workingImage(cv, image, maxDim);
    const { gray, scale } = work;
    const pad = PARAMS.pad;
    const steps = { gray: grayToRGBA(cv, gray) };
    let blurred = null, edges = null;
    const best = searchPasses(cv, work, (st) => {
      if (blurred) { blurred.delete(); edges.delete(); }
      blurred = st.blurred; edges = st.edges;
    });
    const result = finish(cv, best, work, w, h);
    const pass = best ? best.pass : 'none';
    const chosen = best ? best.quad : null;
    if (!blurred) {
      const st = edgeSteps(cv, gray, false);
      blurred = st.blurred; edges = st.edges;
    }
    steps.blurred = grayToRGBA(cv, blurred);
    steps.edges = grayToRGBA(cv, edges);

    // All outlines in orange, the chosen page outline in green.
    const contours = new cv.MatVector(), hier = new cv.Mat();
    cv.findContours(edges, contours, hier, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    const canvas = new cv.Mat(gray.rows, gray.cols, cv.CV_8UC4, new cv.Scalar(20, 20, 20, 255));
    cv.drawContours(canvas, contours, -1, new cv.Scalar(255, 150, 0, 255), 1);
    if (chosen) {
      const q = cv.matFromArray(4, 1, cv.CV_32SC2, chosen.flat().map(Math.round));
      const v = new cv.MatVector();
      v.push_back(q);
      cv.polylines(canvas, v, true, new cv.Scalar(40, 220, 90, 255), 3);
      v.delete(); q.delete();
    }
    steps.contours = rgbaFromMat(canvas);
    const contourCount = contours.size();
    canvas.delete(); contours.delete(); hier.delete();

    // Corners drawn on the photo (downscaled for display).
    const src = cv.matFromImageData(image);
    const disp = new cv.Mat();
    cv.resize(src, disp, new cv.Size(gray.cols - 2 * pad, gray.rows - 2 * pad), 0, 0, cv.INTER_AREA);
    src.delete();
    const pts = result.corners.map(([x, y]) => new cv.Point(Math.round((x + 0.5) * scale - 0.5), Math.round((y + 0.5) * scale - 0.5)));
    const color = result.found ? new cv.Scalar(40, 220, 90, 255) : new cv.Scalar(230, 60, 60, 255);
    for (let i = 0; i < 4; i++) cv.line(disp, pts[i], pts[(i + 1) % 4], color, 2);
    for (const p of pts) cv.circle(disp, p, 6, new cv.Scalar(30, 110, 255, 255), -1);
    steps.corners = rgbaFromMat(disp);
    disp.delete();

    steps.flattened = warpPage(cv, image, result.corners, 1000);
    gray.delete(); work.color.delete(); blurred.delete(); edges.delete();
    return { result, steps, pass, contourCount, scale };
  }

  return {
    PARAMS, detectDocument, explainDetection, warpPerspective, warpPage, pageCurves, curveAt, applyEdits, prepareOcr, OCR, orderCorners,
    fullBounds, outputSize,
    // For tests: compare the scoring step by step with the Python reference.
    __test: { clipGlare, flatten, refineCorners },
    internals: { workingImage, passes, edgeSteps, bestQuad, scoreQuad, sideFits, edgeSupport, extremePoints, lineQuads },
  };
});
