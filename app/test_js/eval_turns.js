// Sideways / upside-down pages: does the OCR runner's rule (lib/features/editor/
// ocr_runner.dart: read; if readingScore < 100, read turned 1, 3, then 2 quarter
// turns and keep a turn that scores >= 15 and > 2x the best so far) find the
// right way up? Fake ID cards and ordinary pages from shared/test_fixtures/hard,
// each read upright and as scanned turned 90, 180 and 270 degrees.
//
//   node eval_turns.js [--per 4] [--json out.json]
const fs = require('node:fs');
const path = require('node:path');
const jpeg = require('jpeg-js');
const cvModule = require('@techstark/opencv-js');
const Tesseract = require('tesseract.js');
const S = require('../web/opencv/scanner.js');
const { toResult } = require('../web/ocr/ocr.js');
const { prepareOcrVariants, mergeOcr, littleText } = require('./ocr_merge.js');

const args = process.argv.slice(2);
const opt = (n, d) => (args.includes(`--${n}`) ? args[args.indexOf(`--${n}`) + 1] : d);
const per = Number(opt('per', 4));
const HARD = path.join(__dirname, '..', '..', 'shared', 'test_fixtures', 'hard');
const hard = JSON.parse(fs.readFileSync(path.join(HARD, 'hard_cases.json')));
const encode = (img, q = 85) => Buffer.from(jpeg.encode({ data: img.data, width: img.width, height: img.height }, q).data);
const decode = (buf) => jpeg.decode(buf, { useTArray: true, formatAsRGBA: true });

// Same as readingScore in lib/services/ocr/ocr_result.dart.
const realWord = /[\p{L}\p{M}]{3,}|\p{N}{4,}/gu;
const score = (r) => r.lines.reduce((s, l) => s + (l.text.match(realWord) || []).join('').length * l.confidence, 0);
const POOR = Number(opt('poor', 100)), CLEAR = Number(opt('clear', 15));

(async () => {
  await new Promise((r) => (cvModule.Mat ? r() : (cvModule.onRuntimeInitialized = r)));
  const cv = cvModule;
  const worker = await Tesseract.createWorker('eng', 1, { langPath: path.join(__dirname, '..', 'web', 'ocr', 'lang'), gzip: true, cacheMethod: 'none' });
  const read = async (img) => {
    const { data } = await worker.recognize(encode(img, 92), {}, { blocks: true, text: true });
    return toResult(data, img.width, img.height);
  };
  const turn = (img, t) => {
    if (t % 4 === 0) return img;
    const src = cv.matFromImageData(img), dst = new cv.Mat();
    cv.rotate(src, dst, [cv.ROTATE_90_CLOCKWISE, cv.ROTATE_180, cv.ROTATE_90_COUNTERCLOCKWISE][(t % 4) - 1]);
    const out = { data: new Uint8ClampedArray(dst.data), width: dst.cols, height: dst.rows };
    src.delete();
    dst.delete();
    return out;
  };
  const pipeline = async (img) => {
    const [first, second] = prepareOcrVariants(cv, S, img);
    let r = await read(first);
    if (littleText(r)) r = mergeOcr(r, await read(second()));
    return r;
  };
  // The runner's rule; returns the chosen turn and the result.
  const runner = async (img) => {
    let result = await pipeline(img), turns = 0, best = score(result);
    const first = best;
    if (best < POOR) {
      for (const t of [1, 3, 2]) {
        if (t === 2 && turns !== 0) break;
        const r = await pipeline(turn(img, t));
        const s = score(r);
        if (s >= CLEAR && s > 2 * best) [best, result, turns] = [s, r, t];
      }
    }
    return { turns, result, first };
  };
  const rows = [];
  const sets = { aadhaar: per, pan: per, plain_white: Math.ceil(per / 2), handwritten: Math.ceil(per / 2) };
  for (const [kind, n] of Object.entries(sets)) {
    for (const it of hard.cases[kind].slice(0, n)) {
      const photo = decode(fs.readFileSync(path.join(HARD, it.file)));
      const flat = S.warpPage(cv, photo, it.corners, 2480);
      const upright = decode(encode(S.applyEdits(cv, flat, { filter: 'magic_color' }, 2480)));
      for (const scanned of [0, 1, 2, 3]) {
        const { turns, result, first } = await runner(turn(upright, scanned));
        const right = (scanned + turns) % 4 === 0;
        const f = it.fields;
        const num = f ? result.text.replace(/\s+/g, '').includes(f.number.replace(/\s+/g, '')) : null;
        rows.push({ file: it.file, kind, scannedTurned: scanned * 90, firstScore: Math.round(first), turnedBy: turns * 90, upright: right, numberRead: num });
        console.log(JSON.stringify(rows.at(-1)));
      }
    }
  }
  await worker.terminate();
  const sum = {};
  for (const r of rows) {
    const k = `${r.kind} ${r.scannedTurned}°`;
    sum[k] ??= { pages: 0, upright: 0, number: 0 };
    sum[k].pages++;
    sum[k].upright += r.upright ? 1 : 0;
    sum[k].number += r.numberRead ? 1 : 0;
  }
  console.table(sum);
  if (opt('json')) fs.writeFileSync(opt('json'), JSON.stringify({ engine: 'Tesseract.js (web)', summary: sum, rows }, null, 1));
})();
