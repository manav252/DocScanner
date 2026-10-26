// OCR accuracy on the fake ID cards (shared/test_fixtures/hard: aadhaar_*, pan_*)
// with the web app's OCR engine (Tesseract.js, same build and language data).
//
//   node eval_ocr.js [--pipeline before|after] [--json out.json] [--dump texts.json]
//
// --dump saves the recognised text of every card (and of 6 ordinary pages,
// as negatives) for the Dart ID-card classifier tests.
//
// Each card is flattened at its true corners and made into the page image the
// app keeps (Magic Color, JPEG), then read as the app's OCR runner reads it.
// A field counts as read when it appears exactly in the text (name: any case;
// number: spaces ignored).
const fs = require('node:fs');
const path = require('node:path');
const jpeg = require('jpeg-js');
const cvModule = require('@techstark/opencv-js');
const Tesseract = require('tesseract.js');
const S = require('../web/opencv/scanner.js');
const { toResult } = require('../web/ocr/ocr.js');
const prep = () => require('./ocr_merge.js');

const args = process.argv.slice(2);
const opt = (n, d) => (args.includes(`--${n}`) ? args[args.indexOf(`--${n}`) + 1] : d);
const pipeline = opt('pipeline', 'after');
const HARD = path.join(__dirname, '..', '..', 'shared', 'test_fixtures', 'hard');
const hard = JSON.parse(fs.readFileSync(path.join(HARD, 'hard_cases.json')));

const encode = (img, q = 85) => Buffer.from(jpeg.encode({ data: img.data, width: img.width, height: img.height }, q).data);

(async () => {
  await new Promise((r) => (cvModule.Mat ? r() : (cvModule.onRuntimeInitialized = r)));
  const cv = cvModule;
  const worker = await Tesseract.createWorker('eng', 1, {
    langPath: path.join(__dirname, '..', 'web', 'ocr', 'lang'),
    gzip: true,
    cacheMethod: 'none',
  });
  const read = async (img) => {
    const { data } = await worker.recognize(encode(img, 92), {}, { blocks: true, text: true });
    return toResult(data, img.width, img.height);
  };
  const out = {};
  const dump = {};
  const readPage = async (it) => {
    const photo = jpeg.decode(fs.readFileSync(path.join(HARD, it.file)), { useTArray: true, formatAsRGBA: true });
    const flat = S.warpPage(cv, photo, it.corners, 2480);
    const render = jpeg.decode(encode(S.applyEdits(cv, flat, { filter: 'magic_color' }, 2480)), { useTArray: true, formatAsRGBA: true });
    return { render, flat };
  };
  for (const kind of ['aadhaar', 'pan']) {
    const score = { name: 0, dob: 0, number: 0, cards: 0 };
    for (const it of hard.cases[kind]) {
      const photo = jpeg.decode(fs.readFileSync(path.join(HARD, it.file)), { useTArray: true, formatAsRGBA: true });
      const flat = S.warpPage(cv, photo, it.corners, 2480);
      // The page image the app stores (render.jpg): Magic Color, JPEG 85.
      const render = jpeg.decode(encode(S.applyEdits(cv, flat, { filter: 'magic_color' }, 2480)), {
        useTArray: true,
        formatAsRGBA: true,
      });
      let result;
      if (pipeline === 'before') {
        result = await read(render); // one pass on the stored page image (<= 2400 px: no resizing)
      } else {
        const { prepareOcrVariants, mergeOcr, littleText } = prep();
        const [first, second] = prepareOcrVariants(cv, S, render);
        result = await read(first);
        if (littleText(result)) result = mergeOcr(result, await read(second()));
      }
      dump[it.file] = { text: result.text, width: render.width, height: render.height, fields: it.fields };
      const text = result.text, flatText = text.replace(/\s+/g, '');
      const f = it.fields;
      score.cards++;
      if (text.toLowerCase().includes(f.name.toLowerCase())) score.name++;
      if (text.includes(f.dob)) score.dob++;
      if (flatText.includes(f.number.replace(/\s+/g, ''))) score.number++;
    }
    out[kind] = score;
    console.log(`${kind}: name ${score.name}/${score.cards}, DOB ${score.dob}/${score.cards}, number ${score.number}/${score.cards}`);
  }
  if (opt('dump')) {
    for (const it of hard.cases.handwritten.slice(0, 3).concat(hard.cases.plain_white.slice(1, 4))) {
      const { render } = await readPage(it);
      const [first] = prep().prepareOcrVariants(cv, S, render);
      dump[it.file] = { text: (await read(first)).text, width: render.width, height: render.height, fields: null };
    }
    fs.writeFileSync(opt('dump'), JSON.stringify(dump, null, 1));
  }
  await worker.terminate();
  if (opt('json')) fs.writeFileSync(opt('json'), JSON.stringify({ pipeline, engine: 'Tesseract.js (web)', ...out }, null, 1));
})();
