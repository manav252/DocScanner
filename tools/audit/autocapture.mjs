// Auto-capture through the real web camera code, in headless Chrome at a
// phone viewport (headless WebKit does not play camera-like video streams):
// the camera is replaced by a video of a test photo (a page on a desk) with a
// little hand shake. Measures how long until the page
// is captured (the corner screen with "Keep scan" opens).
//
//   node autocapture.mjs [appUrl] [--label name] [--photo tilted_paper] [--shake 2] [--runs 3]
// Writes docs/testing/autocapture-<label>.json.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (n, d) => (args.includes(`--${n}`) ? args[args.indexOf(`--${n}`) + 1] : d);
const appUrl = args.find((a) => a.startsWith('http')) ?? 'http://127.0.0.1:8091/app/';
const label = opt('label', 'run');
const photo = opt('photo', 'tilted_paper');
const shake = Number(opt('shake', 2));
const runs = Number(opt('runs', 3));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const photoBytes = fs.readFileSync(path.join(here, '../../shared/test_fixtures', `${photo}.jpg`));

const results = [];
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
try {
  for (let run = 0; run < runs; run++) {
    const context = await browser.createBrowserContext();
    const page = await context.newPage();
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true });
    await page.setRequestInterception(true);
    page.on('request', (r) =>
      r.url().endsWith('/__camera.jpg') ? r.respond({ body: photoBytes, contentType: 'image/jpeg' }) : r.continue(),
    );
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    // The "camera": a 1280x720 stream of the photo (scaled to fill), shaking by a few px.
    await page.evaluateOnNewDocument((shake) => {
      // Headless WebKit may have no media devices at all: provide them.
      if (!navigator.mediaDevices) Object.defineProperty(navigator, 'mediaDevices', { value: {}, configurable: true });
      navigator.mediaDevices.getUserMedia = async () => {
        const img = new Image();
        img.src = '/__camera.jpg';
        await img.decode();
        const c = document.createElement('canvas');
        c.width = 720;
        c.height = 1280; // portrait, like a phone
        const g = c.getContext('2d');
        setInterval(() => {
          const dx = (Math.random() - 0.5) * 2 * shake, dy = (Math.random() - 0.5) * 2 * shake;
          // The whole photo across the width (the page fully in view), the rest
          // of the frame the photo's own desk, stretched.
          const s = 720 / img.width, h = img.height * s, y = (1280 - h) / 2;
          g.drawImage(img, 0, 0, img.width, 4, 0, 0, 720, y + 1);
          g.drawImage(img, 0, img.height - 4, img.width, 4, 0, y + h - 1, 720, 1280 - y - h + 1);
          g.drawImage(img, dx, y + dy, 720, h);
        }, 33);
        return c.captureStream(30);
      };
      navigator.mediaDevices.enumerateDevices = async () => [{ kind: 'videoinput', deviceId: 'fake', label: 'Back Camera', groupId: '' }];
    }, shake);
    const texts = () =>
      page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim()));
    const click = (l) =>
      page.evaluate((l) => {
        const a = [...document.querySelectorAll('flt-semantics')].filter((n) => (n.getAttribute('aria-label') || n.textContent || '').trim() === l);
        (a.find((n) => n.getAttribute('role') === 'button') ?? a[0])?.click();
      }, l);
    await page.goto(appUrl);
    for (let i = 0; i < 60 && !(await texts()).some((t) => t === 'Skip'); i++) await sleep(250);
    await click('Skip');
    await sleep(1500);
    await click('Scan Document');
    const t0 = Date.now();
    let captured = null, lastHint = '';
    while (Date.now() - t0 < 30000) {
      const t = await texts();
      if (t.some((x) => x.includes('Keep scan'))) {
        captured = Date.now() - t0;
        break;
      }
      lastHint = t.find((x) => /Hold still|Move closer|Point the camera|Document found|Too dark|Searching/.test(x)) ?? lastHint;
      await sleep(200);
    }
    const trail = await page.evaluate(() => localStorage.getItem('docscanner.trail') || '');
    if (!captured && process.env.DEBUG) {
      console.log('labels:', (await texts()).filter(Boolean).slice(0, 30).join(' | ').slice(0, 1200));
      await page.screenshot({ path: process.env.DEBUG });
    }
    results.push({ run, capturedAfterMs: captured, lastHint: captured ? '' : lastHint.slice(0, 120), errors: errors.slice(0, 3) });
    console.log(JSON.stringify(results.at(-1)), captured ? '' : `\ntrail: ${trail.slice(-400)}`);
    await context.close();
  }
} finally {
  await browser.close();
}
fs.writeFileSync(
  path.join(here, `../../docs/testing/autocapture-${label}.json`),
  JSON.stringify({ label, engine: 'Chrome (headless), 390x844 phone viewport', photo, shakePx: shake, runs: results }, null, 1),
);
