/*
 * Web Worker that runs the OpenCV pipeline off the UI thread.
 *
 * Requests  {id, type: 'detect', image: {data: ArrayBuffer(RGBA), width, height}}
 *           {id, type: 'detectEncoded', bytes: ArrayBuffer(JPEG/PNG/WebP)}
 *           {id, type: 'warpEncoded', bytes, corners: [[x,y] x4], maxSide, quality (0..1)} -> JPEG ArrayBuffer
 *           {id, type: 'processEncoded', bytes, edits: {filter, turns, crop}, maxSide?, quality} -> JPEG ArrayBuffer
 *           {id, type: 'normalizeEncoded', bytes, maxSide, quality} -> {data: JPEG ArrayBuffer, width, height}
 *           {id, type: 'prepareOcr', bytes, contrast, quality} -> JPEG ArrayBuffer
 * Replies   {id, ok: true, result} | {id, ok: false, error}
 * Posts {type: 'ready'} once opencv.js (WASM) has initialised.
 */
/* global importScripts, DocScanner */
// Pass our own ?v=<build> on, so the pipeline scripts are never stale either.
const VERSION = self.location.search;
importScripts('opencv.js' + VERSION, 'scanner.js' + VERSION);

// opencv.js exports a thenable Module: never resolve a Promise *with* it.
const ready = new Promise((resolve) => (self.cv.Mat ? resolve() : (self.cv.onRuntimeInitialized = resolve)));
ready.then(() => self.postMessage({ type: 'ready' }));

// Always apply the EXIF orientation explicitly: some browsers (older Safari) ignore it
// by default while <img>/Flutter apply it, which made corners and pixels disagree.
const ORIENT = { imageOrientation: 'from-image' };

async function decode(bytes) {
  const bitmap = await createImageBitmap(new Blob([bytes]), ORIENT);
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close();
  const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
  release(canvas);
  return img;
}

// Free a canvas's memory now (Safari counts canvas memory per page and frees it late).
function release(canvas) {
  canvas.width = 0;
  canvas.height = 0;
}

// Live tracking state: the last frame's page outline.
const live = { corners: null, width: 0, height: 0, at: 0, count: 0 };

const asImage = (img) => ({ data: new Uint8ClampedArray(img.data), width: img.width, height: img.height });

self.onmessage = async (e) => {
  const { id, type } = e.data;
  try {
    await ready;
    const cv = self.cv;
    let result;
    if (type === 'detect') {
      // Live frames: follow the page from frame to frame (see trackQuad).
      const img = asImage(e.data.image);
      const fresh = !live.corners || live.width !== img.width || live.height !== img.height || Date.now() - live.at > 1000;
      const full = fresh || ++live.count % DocScanner.PARAMS.track_full_every === 0;
      result = DocScanner.detectDocument(cv, img, undefined, fresh ? null : live.corners, full);
      if (result.found) Object.assign(live, { corners: result.corners, width: img.width, height: img.height, at: Date.now() });
      else live.corners = null;
    } else if (type === 'detectEncoded') {
      const img = await decode(e.data.bytes);
      result = { ...DocScanner.detectDocument(cv, img), width: img.width, height: img.height };
    } else if (type === 'normalizeEncoded') {
      const probe = await createImageBitmap(new Blob([e.data.bytes]), ORIENT);
      const s = Math.min(1, e.data.maxSide / Math.max(probe.width, probe.height));
      const w = Math.max(1, Math.round(probe.width * s)), h = Math.max(1, Math.round(probe.height * s));
      const canvas = new OffscreenCanvas(w, h);
      const ctx = canvas.getContext('2d');
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(probe, 0, 0, w, h);
      probe.close();
      const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: e.data.quality });
      release(canvas);
      const data = await blob.arrayBuffer();
      self.postMessage({ id, ok: true, result: { data, width: w, height: h } }, [data]);
      return;
    } else if (type === 'warpEncoded' || type === 'processEncoded' || type === 'prepareOcr') {
      // From engine_bridge.js (iPhone): raw pixels in, raw pixels out (the page encodes).
      const img = e.data.image ? asImage(e.data.image) : await decode(e.data.bytes);
      const out =
        type === 'warpEncoded'
          ? DocScanner.warpPage(cv, img, e.data.corners, e.data.maxSide)
          : type === 'prepareOcr'
            ? DocScanner.prepareOcr(cv, img, e.data.contrast ? 'contrast' : 'main')
            : DocScanner.applyEdits(cv, img, e.data.edits, e.data.maxSide);
      if (e.data.raw) {
        const data = out.data.buffer;
        self.postMessage({ id, ok: true, result: { data, width: out.width, height: out.height } }, [data]);
        return;
      }
      const canvas = new OffscreenCanvas(out.width, out.height);
      canvas.getContext('2d').putImageData(new ImageData(out.data, out.width, out.height), 0, 0);
      const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: e.data.quality });
      release(canvas);
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
