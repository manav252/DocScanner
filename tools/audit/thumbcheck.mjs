// The "thumbnail stuck on a spinner" bug, before vs after: a 14-page document
// whose first page has no stored thumbnail (as left by an interrupted save).
//   node thumbcheck.mjs <appUrl> <label>
// Saves docs/testing/thumb-<label>.png (the home screen after 12 s) and prints
// whether the thumbnail exists in storage by then.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const [appUrl = 'http://localhost:8080/app/', label = 'run'] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 900, height: 700 });
  await page.goto(appUrl, { waitUntil: 'networkidle2' });
  await page.waitForSelector('flt-semantics-host flt-semantics', { timeout: 30000 });
  await page.evaluate(async () => {
    const img = await createImageBitmap(await (await fetch('/img/sample-page.jpg')).blob());
    const jpeg = async (w, h) => {
      const c = new OffscreenCanvas(w, h);
      c.getContext('2d').drawImage(img, 0, 0, w, h);
      return new Uint8Array(await (await c.convertToBlob({ type: 'image/jpeg', quality: 0.9 })).arrayBuffer());
    };
    const [source, render, thumb] = [await jpeg(1512, 2016), await jpeg(1240, 1653), await jpeg(270, 360)];
    const db = await new Promise((res) => {
      const r = indexedDB.open('docscanner', 1);
      r.onsuccess = () => res(r.result);
    });
    const put = (k, v) =>
      new Promise((res) => {
        const t = db.transaction('kv', 'readwrite');
        t.objectStore('kv').put(v, k);
        t.oncomplete = res;
      });
    const pages = [];
    for (let p = 0; p < 14; p++) {
      const id = `cwt-${p}`;
      pages.push({ id, sw: 1512, sh: 2016, corners: [[0, 0], [1511, 0], [1511, 2015], [0, 2015]],
        edits: { filter: 'magic_color', turns: 0, crop: [0, 0, 1, 1] }, rev: 1, rw: 1240, rh: 1653, srcVer: 0, ocrRev: -1 });
      await put(`page/${id}/source.jpg`, source);
      await put(`page/${id}/render.jpg`, render);
      if (p > 0) await put(`page/${id}/thumb.jpg`, thumb); // page 1's thumbnail is missing
    }
    const t = new Date().toISOString();
    const doc = { id: 'cwt', title: 'CWT', created: t, updated: t, pages, rev: 1, remoteId: null, syncedRev: -1, deleted: false, backup: false };
    await put('doc/cwt.json', new TextEncoder().encode(JSON.stringify(doc)));
    const s = { onboardingDone: true };
    await put('app/settings.json', new TextEncoder().encode(JSON.stringify(s)));
    db.close();
  });
  await page.goto(appUrl, { waitUntil: 'domcontentloaded' });
  await sleep(12000);
  await page.screenshot({ path: path.join(here, `../../docs/testing/thumb-${label}.png`) });
  const thumbStored = await page.evaluate(
    () =>
      new Promise((res) => {
        const r = indexedDB.open('docscanner', 1);
        r.onsuccess = () => {
          const q = r.result.transaction('kv').objectStore('kv').get('page/cwt-0/thumb.jpg');
          q.onsuccess = () => res(!!q.result);
        };
      }),
  );
  const labels = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => n.getAttribute('aria-label') || '').filter((l) => /preview/i.test(l)));
  console.log(JSON.stringify({ label, thumbStoredAfter12s: thumbStored, previewStates: labels }));
} finally {
  await browser.close();
}
