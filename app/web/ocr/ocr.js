/*
 * On-device OCR for the web build: Tesseract.js 7 (WASM), self-hosted under
 * ocr/ so it works offline. Loaded lazily on first use; one worker per language.
 *
 *   await DocScannerOcr.recognize(Uint8Array jpegOrPng, 'eng' | 'hin')
 *     -> {text, width, height, lines: [{text, box: [left, top, width, height] (0..1), confidence (0..1)}]}
 *
 * Low-confidence lines and lines without real words are dropped, so a photo
 * with no text returns no lines instead of random letters.
 */
(function (root, factory) {
  const api = factory(root);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.DocScannerOcr = api;
})(typeof self !== 'undefined' ? self : this, function (root) {
  'use strict';

  /** Minimum Tesseract word confidence (0-100). Words below it are dropped, so a
   * misread word disappears instead of showing up wrong. */
  const MIN_CONFIDENCE = 50;
  const workers = {};

  function baseUrl() {
    return new URL('ocr/', root.document.baseURI).href;
  }

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const s = root.document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = () => reject(new Error(`failed to load ${src}`));
      root.document.head.appendChild(s);
    });
  }

  /** 'hin' also reads English (documents in India usually mix both). */
  function langs(lang) {
    return lang === 'hin' ? 'hin+eng' : 'eng';
  }

  async function worker(lang) {
    const key = langs(lang);
    if (!workers[key]) {
      workers[key] = (async () => {
        const base = baseUrl();
        if (!root.Tesseract) await loadScript(base + 'tesseract.min.js');
        return root.Tesseract.createWorker(
          key,
          1 /* LSTM only */,
          {
            workerPath: base + 'worker.min.js',
            corePath: base, // picks the (relaxed)SIMD or plain LSTM core the browser supports
            langPath: base + 'lang',
            gzip: true,
          },
          // Tesseract's internal notes ("Image too small to scale", "Line cannot be
          // recognized" on tiny specks) are not errors; keep them out of the console.
          { debug_file: '/dev/null' },
        );
      })().catch((e) => {
        delete workers[key];
        throw e;
      });
    }
    return workers[key];
  }

  /** A line counts as text when at least half its visible characters are letters/digits (any script). */
  function meaningful(text) {
    const visible = text.replace(/\s/gu, '');
    if (visible.length < 2) return false;
    const word = (visible.match(/[\p{L}\p{M}\p{N}]/gu) || []).length;
    return word >= 2 && word / visible.length >= 0.5;
  }

  /** Tesseract output -> filtered lines with boxes normalised to the image size. */
  function toResult(data, width, height) {
    const lines = [];
    for (const block of data.blocks || []) {
      for (const para of block.paragraphs || []) {
        for (const line of para.lines || []) {
          // Keep confident words only; the line box shrinks to them.
          const words = (line.words || []).filter((w) => w.confidence >= MIN_CONFIDENCE && w.text.trim());
          const kept = line.words ? words : line.confidence >= MIN_CONFIDENCE ? [line] : [];
          const text = kept.map((w) => w.text.trim()).join(' ');
          if (!text || !meaningful(text)) continue;
          const x0 = Math.min(...kept.map((w) => w.bbox.x0)), y0 = Math.min(...kept.map((w) => w.bbox.y0));
          const x1 = Math.max(...kept.map((w) => w.bbox.x1)), y1 = Math.max(...kept.map((w) => w.bbox.y1));
          const conf = kept.reduce((s, w) => s + w.confidence, 0) / kept.length;
          lines.push({
            text,
            box: [x0 / width, y0 / height, (x1 - x0) / width, (y1 - y0) / height],
            confidence: Math.round(conf) / 100,
          });
        }
      }
    }
    return { text: lines.map((l) => l.text).join('\n'), width, height, lines };
  }

  async function recognize(bytes, lang) {
    const blob = new Blob([bytes]);
    const bitmap = await createImageBitmap(blob);
    const { width, height } = bitmap;
    bitmap.close();
    const w = await worker(lang || 'eng');
    const { data } = await w.recognize(blob, {}, { blocks: true, text: true });
    return toResult(data, width, height);
  }

  return { recognize, toResult, meaningful, langs, MIN_CONFIDENCE };
});
