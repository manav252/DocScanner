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
const { toResult } = require('../web/ocr/ocr.js');

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
