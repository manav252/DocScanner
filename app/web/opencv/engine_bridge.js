/*
 * Stands between the app and opencv/scanner_worker.js, with the same interface
 * as the Worker (postMessage, onmessage, onerror, terminate).
 *
 * On iPhone and iPad, image files are decoded and JPEGs encoded here, on the
 * page, instead of inside the worker: the app crashed on an iPhone (iOS 26)
 * exactly at the steps that decode/encode images in the worker (taking the
 * photo, opening Crop, importing a PDF page), while the live preview, which
 * sends raw pixels, ran fine. The worker still does all the OpenCV work.
 * `?codec=main` or `?codec=worker` in the URL picks the route (for testing).
 *
 * Every temporary canvas is shrunk to 0x0 after use: Safari counts canvas
 * memory per page and frees it late otherwise.
 */
(function () {
  'use strict';

  const ENCODED = new Set(['detectEncoded', 'normalizeEncoded', 'warpEncoded', 'processEncoded', 'prepareOcr']);
  const ORIENT = { imageOrientation: 'from-image' };

  function mainCodec() {
    const q = new URLSearchParams(location.search).get('codec');
    if (q) return q === 'main';
    const ua = navigator.userAgent;
    return /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  }

  function release(canvas) {
    canvas.width = 0;
    canvas.height = 0;
  }

  /** JPEG/PNG bytes -> {data: ArrayBuffer (RGBA), width, height}, upright, long side <= maxSide. */
  async function decode(bytes, maxSide) {
    const bitmap = await createImageBitmap(new Blob([bytes]), ORIENT);
    const s = maxSide ? Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height)) : 1;
    const w = Math.max(1, Math.round(bitmap.width * s)), h = Math.max(1, Math.round(bitmap.height * s));
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, 0, 0, w, h);
    bitmap.close();
    const data = ctx.getImageData(0, 0, w, h).data.buffer;
    release(canvas);
    return { data, width: w, height: h };
  }

  /** {data (RGBA), width, height} -> JPEG ArrayBuffer. */
  async function encode(img, quality) {
    const canvas = document.createElement('canvas');
    canvas.width = img.width;
    canvas.height = img.height;
    canvas.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(img.data), img.width, img.height), 0, 0);
    const blob = await new Promise((resolve, reject) =>
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('JPEG encoding failed'))), 'image/jpeg', quality),
    );
    release(canvas);
    return blob.arrayBuffer();
  }

  class Bridge {
    constructor(url) {
      this.onmessage = null;
      this.onerror = null;
      this._main = mainCodec();
      this._next = 1;
      this._waiting = new Map(); // bridge request id -> resolve/reject
      this._worker = new Worker(url);
      this._worker.onerror = (e) => this.onerror && this.onerror(e);
      this._worker.onmessage = (e) => {
        const d = e.data;
        if (d && typeof d.id === 'string' && this._waiting.has(d.id)) {
          const w = this._waiting.get(d.id);
          this._waiting.delete(d.id);
          if (d.ok) w.resolve(d.result);
          else w.reject(new Error(d.error));
          return;
        }
        this.onmessage && this.onmessage(e);
      };
    }

    get codec() {
      return this._main ? 'main' : 'worker';
    }

    _reply(data) {
      this.onmessage && this.onmessage({ data });
    }

    /** Ask the worker for raw-pixel work. */
    _work(msg, transfer) {
      const id = `b${this._next++}`;
      return new Promise((resolve, reject) => {
        this._waiting.set(id, { resolve, reject });
        this._worker.postMessage({ ...msg, id }, transfer);
      });
    }

    postMessage(msg, transfer) {
      if (!this._main || !ENCODED.has(msg.type)) {
        this._worker.postMessage(msg, transfer);
        return;
      }
      this._handle(msg).then(
        (result) => this._reply({ id: msg.id, ok: true, result }),
        (err) => this._reply({ id: msg.id, ok: false, error: String(err && err.message ? err.message : err) }),
      );
    }

    async _handle(m) {
      if (m.type === 'normalizeEncoded') {
        const img = await decode(m.bytes, m.maxSide);
        return { data: await encode(img, m.quality), width: img.width, height: img.height };
      }
      const img = await decode(m.bytes);
      if (m.type === 'detectEncoded') {
        const r = await this._work({ type: 'detect', image: img }, [img.data]);
        return { ...r, width: img.width, height: img.height };
      }
      const { bytes, ...rest } = m; // eslint-disable-line no-unused-vars
      const out = await this._work({ ...rest, image: img, raw: true }, [img.data]);
      return encode(out, m.quality);
    }

    terminate() {
      this._worker.terminate();
      for (const w of this._waiting.values()) w.reject(new Error('worker terminated'));
      this._waiting.clear();
    }
  }

  window.DocScannerEngine = { create: (url) => new Bridge(url), mainCodec };
})();
