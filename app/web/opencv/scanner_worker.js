/*
 * Web Worker that runs the OpenCV pipeline off the UI thread.
 *
 * Requests  {id, type: 'detect', image: {data: ArrayBuffer(RGBA), width, height}}
 *           {id, type: 'detectEncoded', bytes: ArrayBuffer(JPEG/PNG/WebP)}
 *           {id, type: 'warpEncoded', bytes, corners: [[x,y] x4], maxSide, quality (0..1)} -> JPEG ArrayBuffer
 *           {id, type: 'processEncoded', bytes, edits: {filter, turns, crop}, maxSide?, quality} -> JPEG ArrayBuffer
 * Replies   {id, ok: true, result} | {id, ok: false, error}
 * Posts {type: 'ready'} once opencv.js (WASM) has initialised.
 */
/* global importScripts, DocScanner */
importScripts('opencv.js', 'scanner.js');

// opencv.js exports a thenable Module: never resolve a Promise *with* it.
const ready = new Promise((resolve) => (self.cv.Mat ? resolve() : (self.cv.onRuntimeInitialized = resolve)));
ready.then(() => self.postMessage({ type: 'ready' }));

async function decode(bytes) {
  const bitmap = await createImageBitmap(new Blob([bytes]));
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close();
  return ctx.getImageData(0, 0, canvas.width, canvas.height);
}

const asImage = (img) => ({ data: new Uint8ClampedArray(img.data), width: img.width, height: img.height });

self.onmessage = async (e) => {
  const { id, type } = e.data;
  try {
    await ready;
    const cv = self.cv;
    let result;
    if (type === 'detect') {
      result = DocScanner.detectDocument(cv, asImage(e.data.image));
    } else if (type === 'detectEncoded') {
      const img = await decode(e.data.bytes);
      result = { ...DocScanner.detectDocument(cv, img), width: img.width, height: img.height };
    } else if (type === 'warpEncoded' || type === 'processEncoded') {
      const img = await decode(e.data.bytes);
      const out =
        type === 'warpEncoded'
          ? DocScanner.warpPerspective(cv, img, e.data.corners, e.data.maxSide)
          : DocScanner.applyEdits(cv, img, e.data.edits, e.data.maxSide);
      const canvas = new OffscreenCanvas(out.width, out.height);
      canvas.getContext('2d').putImageData(new ImageData(out.data, out.width, out.height), 0, 0);
      const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: e.data.quality });
      const jpeg = await blob.arrayBuffer();
      self.postMessage({ id, ok: true, result: jpeg }, [jpeg]);
      return;
    } else {
      throw new Error(`unknown request ${type}`);
    }
    self.postMessage({ id, ok: true, result });
  } catch (err) {
    self.postMessage({ id, ok: false, error: String(err && err.message ? err.message : err) });
  }
};
