// Performance measurements of the real web app in headless Chrome.
//
//   node perf.mjs [appUrl] [--label before|after] [--docs 12] [--pages 14]
//
// Seeds the app's own IndexedDB with large documents (a 14-page "CWT" plus
// others; every page has a source photo, flat, render and thumbnail of
// realistic size, generated from the site's sample photo), then measures:
//   - home load: navigation -> recent scans titles in the accessibility tree
//   - thumbnails: time until every visible card reports its preview loaded
//   - delete: confirm -> card gone, longest frame gap and long tasks meanwhile
//   - scroll: frame intervals while scrolling the Documents list
//   - memory: JS heap after opening and closing the big document 5 times
// Results are appended to docs/testing/perf-<label>.json.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : def;
};
const appUrl = args.find((a) => a.startsWith('http')) ?? 'http://localhost:8080/app/';
const label = opt('label', 'run');
const docCount = Number(opt('docs', 12));
const bigPages = Number(opt('pages', 14));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--enable-precise-memory-info', '--js-flags=--expose-gc'],
});
const result = { label, date: new Date().toISOString(), docs: docCount, bigDocPages: bigPages };
// A run that hangs (browser stuck) ends with an error instead of blocking the batch.
setTimeout(() => {
  result.error = 'watchdog: run took over 8 minutes';
  fs.writeFileSync(path.join(here, `../../docs/testing/perf-${label}.json`), JSON.stringify(result, null, 1));
  process.exit(2);
}, 8 * 60 * 1000).unref();

// Frame sampler + long-task observer, installed before the app starts.
const instrument = () => {
  window.__frames = [];
  let last = performance.now();
  const tick = (t) => {
    window.__frames.push(t - last);
    last = t;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  window.__long = [];
  new PerformanceObserver((l) => {
    for (const e of l.getEntries()) window.__long.push({ start: e.startTime, ms: e.duration });
  }).observe({ type: 'longtask', buffered: true });
};

async function texts(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim()),
  );
}

async function waitFor(page, pred, timeout = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (await page.evaluate(pred)) return Date.now() - t0;
    await sleep(25);
  }
  return null;
}

async function click(page, label, { exact = true, last = false } = {}) {
  const ok = await page.evaluate(
    (label, exact, last) => {
      const nodes = [...document.querySelectorAll('flt-semantics [role], flt-semantics[role]')].filter((n) =>
        ['button', 'link', 'menuitem'].includes(n.getAttribute('role')),
      );
      const text = (n) => (n.getAttribute('aria-label') || n.textContent || '').trim();
      const hits = nodes.filter((n) => (exact ? text(n) === label : text(n).startsWith(label)));
      const hit = last ? hits.at(-1) : hits[0];
      hit?.click();
      return !!hit;
    },
    label,
    exact,
    last,
  );
  if (!ok) throw new Error(`no button "${label}"`);
}

const frameStats = (frames) => {
  const f = frames.filter((x) => x > 0).sort((a, b) => a - b);
  if (!f.length) return null;
  const pct = (p) => +f[Math.min(f.length - 1, Math.floor((p / 100) * f.length))].toFixed(1);
  return { frames: f.length, p50: pct(50), p95: pct(95), max: +f.at(-1).toFixed(1), over50ms: f.filter((x) => x > 50).length };
};

async function heapMB(page) {
  const cdp = await page.createCDPSession();
  await cdp.send('Performance.enable');
  await cdp.send('HeapProfiler.collectGarbage');
  const { metrics } = await cdp.send('Performance.getMetrics');
  await cdp.detach();
  const get = (n) => metrics.find((m) => m.name === n)?.value ?? 0;
  return +(get('JSHeapUsedSize') / 1048576).toFixed(1);
}

try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });
  await page.evaluateOnNewDocument(instrument);
  const cdp0 = await page.createCDPSession();
  await cdp0.send('Performance.enable');

  // ---- seed ----
  await page.goto(appUrl, { waitUntil: 'networkidle2' });
  await page.waitForSelector('flt-semantics-host flt-semantics', { timeout: 30000 });
  const seeded = await page.evaluate(
    async (docCount, bigPages) => {
      const img = await createImageBitmap(await (await fetch('/img/sample-page.jpg')).blob());
      async function jpeg(w, h, q, seed) {
        const c = new OffscreenCanvas(w, h);
        const g = c.getContext('2d');
        g.drawImage(img, 0, 0, w, h);
        // Per-page variation so pages compress like real photos, not identical copies.
        g.fillStyle = `rgba(${seed * 37 % 255},${seed * 91 % 255},${seed * 53 % 255},0.06)`;
        g.fillRect(0, 0, w, h);
        // Sensor-like noise: real 12 MP photos are ~2-4 MB as JPEG.
        if (w > 1000) {
          const tile = g.createImageData(256, 256);
          for (let i = 0; i < tile.data.length; i += 4) {
            const v = Math.random() * 40;
            tile.data[i] = tile.data[i + 1] = tile.data[i + 2] = v;
            tile.data[i + 3] = 40;
          }
          const tc = new OffscreenCanvas(256, 256);
          tc.getContext('2d').putImageData(tile, 0, 0);
          g.fillStyle = g.createPattern(tc, 'repeat');
          g.globalCompositeOperation = 'overlay';
          g.fillRect(0, 0, w, h);
          g.globalCompositeOperation = 'source-over';
        }
        return new Uint8Array(await (await c.convertToBlob({ type: 'image/jpeg', quality: q })).arrayBuffer());
      }
      const source = await jpeg(3024, 4032, 0.92, 1);
      const flat = await jpeg(2400, 3200, 0.92, 2);
      const render = await jpeg(2400, 3200, 0.9, 3);
      const thumb = await jpeg(270, 360, 0.8, 4);
      const db = await new Promise((res, rej) => {
        const r = indexedDB.open('docscanner', 1);
        r.onsuccess = () => res(r.result);
        r.onerror = () => rej(r.error);
      });
      const put = (k, v) =>
        new Promise((res, rej) => {
          const t = db.transaction('kv', 'readwrite');
          t.objectStore('kv').put(v, k);
          t.oncomplete = res;
          t.onerror = () => rej(t.error);
        });
      const enc = new TextEncoder();
      let bytes = 0;
      const now = Date.now();
      for (let d = 0; d < docCount; d++) {
        const n = d === 0 ? bigPages : 1 + (d % 4);
        const pages = [];
        for (let p = 0; p < n; p++) {
          const id = `perf-${d}-${p}`;
          pages.push({ id, sw: 3024, sh: 4032, corners: [[0, 0], [3023, 0], [3023, 4031], [0, 4031]],
            edits: { filter: 'magic_color', turns: 0, crop: [0, 0, 1, 1] }, rev: 1, rw: 2400, rh: 3200, srcVer: 0, ocrRev: -1 });
          for (const [k, v] of [['source', source], ['flat', flat], ['render', render], ['thumb', thumb]]) {
            await put(`page/${id}/${k}.jpg`, v);
            bytes += v.length;
          }
        }
        const t = new Date(now - d * 60000).toISOString();
        const doc = { id: `perf-doc-${d}`, title: d === 0 ? 'CWT' : `Perf document ${d}`, created: t, updated: t,
          pages, rev: 1, remoteId: null, syncedRev: -1, deleted: false, backup: false };
        await put(`doc/perf-doc-${d}.json`, enc.encode(JSON.stringify(doc)));
      }
      // Skip the first-run guide.
      const settings = await new Promise((res) => {
        const t = db.transaction('kv', 'readonly').objectStore('kv').get('app/settings.json');
        t.onsuccess = () => res(t.result);
      });
      const s = settings ? JSON.parse(new TextDecoder().decode(settings)) : {};
      s.onboardingDone = true;
      await put('app/settings.json', enc.encode(JSON.stringify(s)));
      db.close();
      return { mb: +(bytes / 1048576).toFixed(1), perPage: { source: source.length, render: render.length, thumb: thumb.length } };
    },
    docCount,
    bigPages,
  );
  result.seeded = seeded;
  console.log('seeded', seeded);

  // Repeat-visit conditions: let a service worker (if the build has one) finish
  // caching first, so it does not download in the background while we measure.
  if (args.includes('--settle-sw')) {
    for (const t0 = Date.now(); Date.now() - t0 < 90000; await sleep(1000)) {
      const st = await page.evaluate(async () => {
        const reg = await navigator.serviceWorker?.getRegistration();
        if (!reg) return 'none';
        if (!reg.active || reg.installing || reg.waiting) return 'installing';
        return 'active';
      });
      if (st === 'active' || (st === 'none' && Date.now() - t0 > 12000)) break;
    }
    await sleep(2000);
  }
  // ---- home load ----
  console.error('step: home load');
  const t0 = Date.now();
  await page.goto(appUrl, { waitUntil: 'domcontentloaded' });
  const firstCard = await waitFor(page, () =>
    [...document.querySelectorAll('flt-semantics')].some((n) => (n.textContent || n.getAttribute('aria-label') || '').includes('CWT')),
  );
  result.homeLoadMs = firstCard == null ? null : Date.now() - t0;
  // Thumbnails report their state in the accessibility tree ("Page preview" when shown).
  const thumbsMs = await waitFor(
    page,
    () => {
      const labels = [...document.querySelectorAll('flt-semantics')].map((n) => n.getAttribute('aria-label') || '');
      return labels.some((l) => l.includes('Page preview')) && !labels.some((l) => l.includes('Loading page preview'));
    },
    20000,
  );
  result.thumbnailsReadyMs = thumbsMs == null ? 'not reported (no preview state in the accessibility tree)' : Date.now() - t0;
  await sleep(1500);
  result.homeFrames = frameStats(await page.evaluate(() => window.__frames.splice(0)));
  result.homeLongTasks = await page.evaluate(() => window.__long.splice(0).map((e) => Math.round(e.ms)));

  if (args.includes('--only-home')) throw Object.assign(new Error('only-home'), { done: true });
  const onlyDelete = args.includes('--only-delete');
  if (!onlyDelete) {
  // ---- scroll the Documents list ----
  console.error('step: scroll the Documents list');
  await click(page, 'View Documents');
  await waitFor(page, () => [...document.querySelectorAll('flt-semantics')].some((n) => (n.textContent || '').includes('Perf document 3')));
  await sleep(1000);
  await page.evaluate(() => { window.__frames.length = 0; window.__long.length = 0; });
  await page.mouse.move(640, 500);
  for (let i = 0; i < 30; i++) {
    await page.mouse.wheel({ deltaY: 120 });
    await sleep(16);
  }
  for (let i = 0; i < 30; i++) {
    await page.mouse.wheel({ deltaY: -120 });
    await sleep(16);
  }
  await sleep(500);
  result.scroll = frameStats(await page.evaluate(() => window.__frames.splice(0)));
  result.scrollLongTasks = await page.evaluate(() => window.__long.splice(0).map((e) => Math.round(e.ms)));

  // ---- memory: open/close the big document 5 times ----
  console.error('step: memory: open/close the big document 5 times');
  result.heapBeforeMB = await heapMB(page);
  const cycles = args.includes('--no-memory') ? 0 : Number(opt('cycles', 5));
  result.heapEvery5 = [];
  for (let i = 0; i < cycles; i++) {
    if (i > 0 && i % 5 === 0) result.heapEvery5.push(await heapMB(page));
    await click(page, 'CWT', { exact: false });
    await waitFor(page, () => [...document.querySelectorAll('flt-semantics')].some((n) => (n.textContent || '').includes('Page 1 of')));
    await sleep(1500);
    await page.keyboard.press('Escape');
    await page.goBack().catch(() => {});
    await click(page, 'Back').catch(() => {});
    await waitFor(page, () => [...document.querySelectorAll('flt-semantics')].some((n) => (n.textContent || '').includes('Perf document 3')));
    await sleep(500);
  }
  result.heapAfter5OpensMB = await heapMB(page);

  }
  // Fresh Documents screen for the delete.
  console.error('step: Fresh Documents screen for the delete.');
  await page.goto(appUrl, { waitUntil: 'domcontentloaded' });
  await waitFor(page, () => [...document.querySelectorAll('flt-semantics')].some((n) => (n.textContent || '').includes('CWT')));
  await click(page, 'View Documents');
  await waitFor(page, () => [...document.querySelectorAll('flt-semantics')].some((n) => (n.textContent || '').includes('Perf document 3')));
  await sleep(1500);

  // ---- delete the 14-page document ----
  console.error('step: delete the 14-page document');
  await page.evaluate(() => { window.__frames.length = 0; window.__long.length = 0; });
  const cards = await texts(page);
  if (!cards.some((t) => t.includes('CWT'))) throw new Error('CWT card not on screen');
  const tracing = args.includes('--trace-delete');
  const tracePath = path.join(here, '../../docs/testing/raw/delete-trace.json');
  if (tracing) await page.tracing.start({ path: tracePath, categories: ['devtools.timeline', 'disabled-by-default-devtools.timeline', 'blink', 'v8', 'IndexedDB', 'toplevel', 'disabled-by-default-v8.gc'] });
  const profiling = args.includes('--profile-delete');
  const prof = profiling ? await page.createCDPSession() : null;
  if (prof) {
    await prof.send('Profiler.enable');
    await prof.send('Profiler.setSamplingInterval', { interval: 200 });
    await prof.send('Profiler.start');
  }
  const tCard = Date.now();
  await click(page, 'Delete', { exact: true });
  // Old version: a confirmation dialog. New version: deletes at once with Undo.
  // Poll from the click for whichever comes first.
  let dialog = false;
  let goneAfterCard = null;
  for (const t0 = Date.now(); Date.now() - t0 < 3000; await sleep(10)) {
    // The list leaves the accessibility tree a frame before a dialog's buttons arrive:
    // after the card disappears, keep watching 1 s for a dialog before deciding.
    if (goneAfterCard != null && Date.now() - tCard > goneAfterCard + 1000) break;
    // A confirmation dialog hides the list from the accessibility tree, so "CWT gone"
    // alone is not proof: the old dialog is recognised by its Cancel button.
    const st = await page.evaluate(() => {
      const labels = [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim());
      return { dialog: labels.includes('Cancel'), gone: !labels.some((t) => t.includes('CWT')) };
    });
    if (st.dialog) { dialog = true; break; }
    if (st.gone && goneAfterCard == null) goneAfterCard = Date.now() - tCard;
  }
  result.deleteHasConfirmDialog = dialog;
  if (dialog) await sleep(300); // dialog opens
  const tClick = dialog ? Date.now() : tCard;
  if (dialog) await click(page, 'Delete', { exact: true, last: true }); // the dialog's confirm button
  const gone = dialog
    ? await waitFor(page, () => ![...document.querySelectorAll('flt-semantics')].some((n) => (n.textContent || '').includes('CWT')))
    : 0;
  result.deleteCardGoneMs = dialog ? (gone == null ? null : Date.now() - tClick) : goneAfterCard;
  await sleep(2000);
  if (tracing) await page.tracing.stop();
  if (prof) {
    const { profile } = await prof.send('Profiler.stop');
    // Self time per function, from the sampled call tree.
    const byId = new Map(profile.nodes.map((n) => [n.id, n]));
    const self = new Map();
    const dt = profile.timeDeltas;
    profile.samples.forEach((id, i) => {
      const n = byId.get(id);
      const key = `${n.callFrame.functionName || '(anonymous)'} ${n.callFrame.url.split('/').pop()}:${n.callFrame.lineNumber}`;
      self.set(key, (self.get(key) ?? 0) + (dt[i] ?? 0) / 1000);
    });
    result.deleteProfileTop = [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, 30).map(([k, ms]) => `${ms.toFixed(1)} ms  ${k}`);
  }
  result.deleteFrames = frameStats(await page.evaluate(() => window.__frames.splice(0)));
  result.deleteLongTasks = await page.evaluate(() => window.__long.splice(0).map((e) => Math.round(e.ms)));
  await sleep(6000); // past the Undo window
  result.deleteStorageGone = await page.evaluate(
    () =>
      new Promise((res) => {
        const r = indexedDB.open('docscanner', 1);
        r.onsuccess = () => {
          const q = r.result.transaction('kv').objectStore('kv').getAllKeys(IDBKeyRange.bound('page/perf-0-', 'page/perf-0-￿'));
          q.onsuccess = () => { res(q.result.length === 0); r.result.close(); };
        };
      }),
  );
} catch (e) {
  if (!e.done) result.error = String(e.stack || e);
} finally {
  await browser.close();
}

console.log(JSON.stringify(result, null, 1));
const out = path.join(here, `../../docs/testing/perf-${label}.json`);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(result, null, 1));

process.exit(0);
