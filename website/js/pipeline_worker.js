// Loads the same opencv.js and scanner.js files the web app uses (app/ next to the site).
// Relative to this worker (js/), so the site also works under a sub-path (GitHub Pages).
importScripts('../app/opencv/opencv.js', '../app/opencv/scanner.js');

// opencv.js exports a thenable Module: never resolve a Promise *with* it (same as the app's worker).
const ready = new Promise((resolve) => (self.cv.Mat ? resolve() : (self.cv.onRuntimeInitialized = resolve)));
ready.then(() => self.postMessage({ type: 'ready' }));

self.onmessage = async ({ data }) => {
  if (data.type !== 'explain') return;
  await ready;
  try {
    const t0 = performance.now();
    const x = self.DocScanner.explainDetection(self.cv, data.image);
    const ms = Math.round(performance.now() - t0);
    const transfer = Object.values(x.steps).map((s) => s.data.buffer);
    self.postMessage({ type: 'result', ms, result: x.result, pass: x.pass, contourCount: x.contourCount, steps: x.steps }, transfer);
  } catch (e) {
    self.postMessage({ type: 'error', message: String(e && e.message ? e.message : e) });
  }
};
