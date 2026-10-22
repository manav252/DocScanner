/*
 * On-device OCR for the web build: Tesseract.js 7 (WASM), self-hosted under
 * ocr/ so it works offline. Loaded lazily on first use; one worker is reused.
 *
 *   await DocScannerOcr.recognize(Uint8Array jpegOrPng)
 *     -> {text, width, height, lines: [{text, box: [left, top, width, height] (0..1), confidence}]}
 */
(function (root, factory) {
  const api = factory(root);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.DocScannerOcr = api;
})(typeof self !== 'undefined' ? self : this, function (root) {
  'use strict';

  const MIN_CONFIDENCE = 30;
  let workerPromise = null;

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

  async function worker() {
    if (!workerPromise) {
      workerPromise = (async () => {
        const base = baseUrl();
        if (!root.Tesseract) await loadScript(base + 'tesseract.min.js');
        return root.Tesseract.createWorker('eng', 1 /* LSTM only */, {
          workerPath: base + 'worker.min.js',
          corePath: base, // picks the (relaxed)SIMD or plain LSTM core the browser supports
          langPath: base + 'lang',
          gzip: true,
        });
      })().catch((e) => {
        workerPromise = null;
        throw e;
      });
    }
    return workerPromise;
  }

  /** Tesseract output -> lines with boxes normalised to the image size. */
  function toResult(data, width, height) {
    const lines = [];
    for (const block of data.blocks || []) {
      for (const para of block.paragraphs || []) {
        for (const line of para.lines || []) {
          const text = (line.text || '').trim();
          if (!text || line.confidence < MIN_CONFIDENCE) continue;
          const { x0, y0, x1, y1 } = line.bbox;
          lines.push({
            text,
            box: [x0 / width, y0 / height, (x1 - x0) / width, (y1 - y0) / height],
            confidence: Math.round(line.confidence),
          });
        }
      }
    }
    return { text: lines.map((l) => l.text).join('\n'), width, height, lines };
  }

  async function recognize(bytes) {
    const blob = new Blob([bytes]);
    const bitmap = await createImageBitmap(blob);
    const { width, height } = bitmap;
    bitmap.close();
    const w = await worker();
    const { data } = await w.recognize(blob, {}, { blocks: true, text: true });
    return toResult(data, width, height);
  }

  return { recognize, toResult };
});
