// Tests for web/opencv/scanner.js against the shared fixtures (run: npm test)
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const jpeg = require('jpeg-js');
const cvModule = require('@techstark/opencv-js');
const S = require('../web/opencv/scanner.js');

const FIX = path.join(__dirname, '..', '..', 'shared', 'test_fixtures');
const spec = JSON.parse(fs.readFileSync(path.join(FIX, 'expected_corners.json')));
const pyRef = JSON.parse(fs.readFileSync(path.join(FIX, 'python_reference.json')));
const params = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'shared', 'detector_params.json')));
const [W, H] = spec.image_size;
const TOL = 0.01 * Math.hypot(W, H);

const load = (n) => jpeg.decode(fs.readFileSync(path.join(FIX, `${n}.jpg`)), { useTArray: true, formatAsRGBA: true });
const maxErr = (a, b) => Math.max(...a.map((p, i) => Math.hypot(p[0] - b[i][0], p[1] - b[i][1])));

let cv;
test.before(async () => {
  // The module is a thenable, so never resolve a Promise *with* it (that recurses forever).
  await new Promise((r) => (cvModule.Mat ? r() : (cvModule.onRuntimeInitialized = r)));
  cv = cvModule;
});

test('params match shared/detector_params.json', () => assert.deepStrictEqual(S.PARAMS, params));

// Hard cases: same page found as the Python reference, within 6 px wherever the
// reference is right; success per case -> docs/testing/detection-after-web.json.
const HARD = path.join(FIX, 'hard');
const hard = JSON.parse(fs.readFileSync(path.join(HARD, 'hard_cases.json')));
const hardRef = JSON.parse(fs.readFileSync(path.join(HARD, 'python_reference.json')));
const hardResults = {};
for (const [name, items] of Object.entries(hard.cases)) {
  test(`hard case: ${name}`, () => {
    let ok = 0;
    for (const it of items) {
      const img = jpeg.decode(fs.readFileSync(path.join(HARD, it.file)), { useTArray: true, formatAsRGBA: true });
      const d = S.detectDocument(cv, img);
      const py = hardRef[it.file];
      assert.strictEqual(d.found, py.found, `${it.file}: found differs from the Python reference`);
      if (!d.found) continue;
      const truth = S.orderCorners(it.corners);
      if (maxErr(py.corners, truth) < TOL) {
        const diff = maxErr(d.corners, py.corners);
        assert.ok(diff < 6, `${it.file}: differs from the Python reference by ${diff.toFixed(1)}px`);
      }
      if (maxErr(d.corners, truth) < TOL) ok++;
    }
    hardResults[name] = { success: ok, total: items.length };
  });
}
/** How much the red rule under the page title bends (% of page height); RGBA image. */
function ruleBend({ data, width: w, height: h }) {
  const ys = [];
  for (let x = Math.trunc(0.12 * w); x < Math.trunc(0.88 * w); x += 4) {
    const rows = [];
    for (let y = Math.trunc(0.05 * h); y < Math.trunc(0.3 * h); y++) {
      const i = (y * w + x) * 4;
      if (data[i] - data[i + 2] > 50 && data[i] > 110) rows.push(y);
    }
    if (rows.length) ys.push(rows[rows.length >> 1]);
  }
  return ((Math.max(...ys) - Math.min(...ys)) / h) * 100;
}

test('curved pages: same edge curves as the reference, and they come out flat', () => {
  for (const items of Object.values(hard.cases)) {
    for (const it of items) {
      const img = jpeg.decode(fs.readFileSync(path.join(HARD, it.file)), { useTArray: true, formatAsRGBA: true });
      const curves = S.pageCurves(cv, img, it.corners);
      const py = hardRef[it.file].curves;
      assert.strictEqual(curves === null, py === null, `${it.file}: curved or not differs from the reference`);
      if (!curves) continue;
      curves.forEach((c, k) => {
        for (const t of [0.25, 0.5, 0.75]) {
          const diff = Math.abs(S.curveAt(c, t) - S.curveAt(py[k], t));
          assert.ok(diff < 4, `${it.file} side ${k} at ${t}: ${diff.toFixed(1)} px from the reference`);
        }
      });
      const plain = ruleBend(S.warpPerspective(cv, img, it.corners)), flat = ruleBend(S.warpPage(cv, img, it.corners));
      assert.ok(plain > 2.5 && flat < 1, `${it.file}: bend ${plain.toFixed(2)}% -> ${flat.toFixed(2)}%`);
    }
  }
});

test.after(() => {
  if (Object.keys(hardResults).length) {
    fs.writeFileSync(path.join(__dirname, '..', '..', 'docs', 'testing', 'detection-after-web.json'), JSON.stringify(hardResults, null, 1));
  }
});

for (const [name, c] of Object.entries(spec.cases)) {
  test(`fixture ${name}`, () => {
    const d = S.detectDocument(cv, load(name));
    assert.strictEqual(d.found, c.found, c.note);
    if (c.found) {
      const e = maxErr(d.corners, c.corners);
      assert.ok(e < TOL, `${name}: error ${e.toFixed(1)}px`);
      const py = maxErr(d.corners, pyRef[name].corners);
      assert.ok(py < 6, `${name}: differs from Python reference by ${py.toFixed(1)}px`);
    } else assert.deepStrictEqual(d.corners, S.fullBounds(W, H));
  });
}

test('orderCorners handles any input order and rotation', () => {
  const r = [[100, 100], [300, 100], [300, 400], [100, 400]];
  for (const deg of [0, 10, 30, 44, -20, -44]) {
    const a = (deg * Math.PI) / 180, c = [200, 250];
    const rot = r.map(([x, y]) => [c[0] + (x - c[0]) * Math.cos(a) - (y - c[1]) * Math.sin(a), c[1] + (x - c[0]) * Math.sin(a) + (y - c[1]) * Math.cos(a)]);
    for (const perm of [[0, 1, 2, 3], [2, 0, 3, 1], [3, 2, 1, 0]]) {
      assert.ok(maxErr(S.orderCorners(perm.map((i) => rot[i])), rot) < 1e-6);
    }
  }
});

test('blank image falls back to bounds', () => {
  const img = { data: new Uint8ClampedArray(640 * 480 * 4).fill(128), width: 640, height: 480 };
  const d = S.detectDocument(cv, img);
  assert.strictEqual(d.found, false);
  assert.deepStrictEqual(d.corners, S.fullBounds(640, 480));
});

test('explainDetection: same corners as detectDocument, an image for every step', () => {
  const name = Object.entries(spec.cases).find(([, c]) => c.found)[0];
  const img = load(name);
  const x = S.explainDetection(cv, img);
  assert.deepStrictEqual(x.result, S.detectDocument(cv, img));
  for (const step of ['gray', 'blurred', 'edges', 'contours', 'corners', 'flattened']) {
    const s = x.steps[step];
    assert.ok(s && s.width > 0 && s.height > 0 && s.data.length === s.width * s.height * 4, step);
  }
  assert.ok(x.contourCount > 0);
  assert.notStrictEqual(x.pass, 'none');
  // Edges are binary; the working image is <= 500 px + padding.
  assert.ok(Math.max(x.steps.edges.width, x.steps.edges.height) <= S.PARAMS.max_dim + 2 * S.PARAMS.pad);
  const e = x.steps.edges.data;
  for (let i = 0; i < e.length; i += 4 * 97) assert.ok(e[i] === 0 || e[i] === 255);
});

test('explainDetection on a blank image: nothing found, full-photo corners', () => {
  const img = { data: new Uint8ClampedArray(320 * 240 * 4).fill(128), width: 320, height: 240 };
  const x = S.explainDetection(cv, img);
  assert.strictEqual(x.result.found, false);
  assert.strictEqual(x.pass, 'none');
  assert.strictEqual(x.steps.flattened.width, 319); // corner-to-corner distance of a 320 px photo
});

test('warp produces page-shaped output', () => {
  const img = load('tilted_paper');
  const out = S.warpPerspective(cv, img, spec.cases.tilted_paper.corners, 800);
  assert.strictEqual(Math.max(out.width, out.height), 800);
  assert.strictEqual(out.data.length, out.width * out.height * 4);
  assert.ok(out.width / out.height > 0.65 && out.width / out.height < 0.85);
});

test('speed on 720x1280 frame', () => {
  const big = load('cluttered_background');
  const m = cv.matFromImageData(big), r = new cv.Mat();
  cv.resize(m, r, new cv.Size(720, 1280));
  const frame = { data: new Uint8ClampedArray(r.data), width: 720, height: 1280 };
  m.delete(); r.delete();
  S.detectDocument(cv, frame);
  const t = performance.now();
  for (let i = 0; i < 20; i++) S.detectDocument(cv, frame);
  const ms = (performance.now() - t) / 20;
  console.log(`  detectDocument 720x1280 (opencv.js wasm, node): ${ms.toFixed(1)} ms`);
  assert.ok(ms < 50);
});

// ---------- filters: parity with scanner_core (Python) ----------
const { PNG } = require('pngjs');
const FILT = path.join(FIX, 'filters');
const loadPng = (n) => {
  const p = PNG.sync.read(fs.readFileSync(path.join(FILT, `${n}.png`)));
  return { data: new Uint8ClampedArray(p.data), width: p.width, height: p.height };
};

// Python saves BGR/gray PNGs; pngjs decodes to RGBA, so channels line up.
function meanAbsDiff(a, b) {
  assert.strictEqual(a.width, b.width);
  assert.strictEqual(a.height, b.height);
  let s = 0;
  for (let i = 0; i < a.data.length; i += 4) for (let c = 0; c < 3; c++) s += Math.abs(a.data[i + c] - b.data[i + c]);
  return s / ((a.data.length / 4) * 3);
}

for (const [filter, maxDiff] of [['original', 0.5], ['grayscale', 1], ['magic_color', 4], ['bw', 6]]) {
  test(`filter ${filter} matches the Python reference`, () => {
    const out = S.applyEdits(cv, loadPng('input'), { filter, turns: 0, crop: [0, 0, 1, 1] });
    const d = meanAbsDiff(out, loadPng(filter));
    // For B&W, 6/255 mean difference == ~2.4% of pixels flipped.
    assert.ok(d < maxDiff, `${filter}: mean abs diff ${d.toFixed(2)}`);
  });
}

test('rotate and crop', () => {
  const inp = loadPng('input');
  const r = S.applyEdits(cv, inp, { filter: 'original', turns: 1, crop: [0, 0, 1, 1] });
  assert.deepStrictEqual([r.width, r.height], [inp.height, inp.width]);
  const c = S.applyEdits(cv, inp, { filter: 'original', turns: 0, crop: [0.25, 0.5, 0.5, 0.25] });
  assert.ok(Math.abs(c.width - inp.width * 0.5) <= 1 && Math.abs(c.height - inp.height * 0.25) <= 1);
  const t = S.applyEdits(cv, inp, { filter: 'magic_color', turns: 2, crop: [0, 0, 1, 1] }, 300);
  assert.strictEqual(Math.max(t.width, t.height), 300);
});

// ---------- OCR (web): the same Tesseract.js build + language data the app serves ----------
const Tesseract = require('tesseract.js');
const { toResult, meaningful } = require('../web/ocr/ocr.js');

test('OCR reads a flattened page and returns normalised line boxes', async () => {
  const worker = await Tesseract.createWorker('eng', 1, {
    langPath: path.join(__dirname, '..', 'web', 'ocr', 'lang'),
    gzip: true,
    cacheMethod: 'none',
  });
  try {
    const png = path.join(FILT, 'magic_color.png');
    const { width, height } = loadPng('magic_color');
    const { data } = await worker.recognize(png, {}, { blocks: true, text: true });
    const r = toResult(data, width, height);
    assert.match(r.text, /QUARTERLY REPORT/);
    assert.match(r.text, /shipping/);
    assert.ok(r.lines.length >= 10, `${r.lines.length} lines`);
    const title = r.lines.find((l) => l.text.includes('QUARTERLY'));
    const [l, t, w, h] = title.box;
    // Title sits in the top-left part of the page.
    assert.ok(l > 0 && l < 0.2 && t > 0 && t < 0.2 && w > 0.3 && w < 0.8 && h > 0.01 && h < 0.06, JSON.stringify(title.box));
    for (const line of r.lines) assert.ok(line.box.every((v) => v >= 0 && v <= 1));
  } finally {
    await worker.terminate();
  }
});

test('OCR reads Hindi (hin+eng) from a Devanagari page', async () => {
  const worker = await Tesseract.createWorker('hin+eng', 1, {
    langPath: path.join(__dirname, '..', 'web', 'ocr', 'lang'),
    gzip: true,
    cacheMethod: 'none',
  });
  try {
    const png = path.join(FIX, 'ocr', 'hindi_page.png');
    const { width, height } = (() => {
      const p = PNG.sync.read(fs.readFileSync(png));
      return { width: p.width, height: p.height };
    })();
    const { data } = await worker.recognize(png, {}, { blocks: true, text: true });
    const r = toResult(data, width, height);
    assert.match(r.text, /भारत/);
    assert.match(r.text, /दस्तावेज़|दस्तावेज/);
    assert.match(r.text, /2026/);
    // The amount was misread (confidence 0), so it is dropped instead of shown wrong.
    assert.doesNotMatch(r.text, /\b250\b/);
    assert.equal(r.lines.length, 4, r.text);
  } finally {
    await worker.terminate();
  }
});

test('OCR on a photo without text returns no lines (no random letters)', async () => {
  const worker = await Tesseract.createWorker('eng', 1, {
    langPath: path.join(__dirname, '..', 'web', 'ocr', 'lang'),
    gzip: true,
    cacheMethod: 'none',
  });
  try {
    const img = path.join(FIX, 'ocr', 'no_text.jpg');
    const { data } = await worker.recognize(img, {}, { blocks: true, text: true });
    const r = toResult(data, 1200, 1600);
    assert.deepStrictEqual(r.lines, [], `unexpected text: ${JSON.stringify(r.text)}`);
  } finally {
    await worker.terminate();
  }
});

test('meaningful-text filter', () => {
  assert.ok(meaningful('Total 42'));
  assert.ok(meaningful('भारत एक देश'));
  for (const junk of ['|', '— —', 'i', '|| ~ ;', '.,;:']) assert.ok(!meaningful(junk), junk);
});
