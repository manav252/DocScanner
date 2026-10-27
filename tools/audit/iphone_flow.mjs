// The web app in WebKit (Safari's engine) on an emulated iPhone: import a
// photo-sized PDF and a 12 MP photo through the real file chooser, scan pages
// with the demo camera (OCR runs after each), open the corner screen. Records
// every page error / console error, whether the app's error screen appeared,
// each step's time, and the peak memory of WebKit's web content process (the
// tab; iOS kills it when it uses too much) and GPU process, sampled every
// 0.5 s.
//
//   node iphone_flow.mjs [appUrl] [--label name]
// Writes docs/testing/iphone-flow-<label>.json; exit code 1 on any failure.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
import { webkit, devices } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (n, d) => (args.includes(`--${n}`) ? args[args.indexOf(`--${n}`) + 1] : d);
const appUrl = args.find((a) => a.startsWith('http')) ?? 'http://127.0.0.1:8091/app/';
const label = opt('label', 'run');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await webkit.launch();
const context = await browser.newContext({ ...devices['iPhone 13'] });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
// The tab's web content process died (on an iPhone: the page reloads / "A problem repeatedly occurred").
let crashed = false;
page.on('crash', () => {
  crashed = true;
  errors.push('TAB CRASHED');
});
page.on('console', (m) => {
  // The local build pings a backend on localhost:8000 that may not be running.
  if (m.type() === 'error' && !/Failed to load resource|Could not connect to the server/.test(m.text())) {
    errors.push(`console: ${m.text().slice(0, 300)}`);
  }
});
const texts = () =>
  page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim()));
async function waitText(needle, timeout = 90000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (crashed) throw new Error('the browser tab crashed');
    const t = await texts();
    if (t.some((x) => x.includes('Something went wrong'))) throw new Error('the app showed its error screen');
    if (t.some((x) => x.includes(needle))) return Date.now() - t0;
    await sleep(200);
  }
  throw new Error(`timed out waiting for "${needle}"`);
}
async function click(label, { last = false } = {}) {
  const ok = await page.evaluate(
    ([label, last]) => {
      const all = [...document.querySelectorAll('flt-semantics')].filter(
        (n) => (n.getAttribute('aria-label') || n.textContent || '').trim() === label,
      );
      const buttons = all.filter((n) => n.getAttribute('role') === 'button');
      const pick = buttons.length ? buttons : all;
      const n = last ? pick.at(-1) : pick[0];
      n?.click();
      return !!n;
    },
    [label, last],
  );
  if (!ok) throw new Error(`no "${label}"`);
  await sleep(700);
}
async function chooseFile(button, file) {
  const [chooser] = await Promise.all([page.waitForEvent('filechooser', { timeout: 15000 }), click(button)]);
  await chooser.setFiles(path.join(here, 'fixtures', file));
}

// Peak resident memory (MB) of Playwright WebKit's tab and GPU processes.
let peak = { tab: 0, gpu: 0 };
function sample() {
  const rows = execSync('ps -axo rss=,command=').toString().split('\n');
  let tab = 0, gpu = 0;
  for (const r of rows) {
    if (!r.includes('ms-playwright')) continue;
    const kb = Number(r.trim().split(/\s+/)[0]);
    if (r.includes('WebContent')) tab += kb;
    else if (r.includes('GPU')) gpu += kb;
  }
  peak = { tab: Math.max(peak.tab, Math.round(tab / 1024)), gpu: Math.max(peak.gpu, Math.round(gpu / 1024)) };
}
const sampler = setInterval(sample, 500);

const steps = [];
async function step(name, fn) {
  peak = { tab: 0, gpu: 0 };
  sample();
  const t0 = Date.now();
  try {
    await fn();
    sample();
    steps.push({ name, ok: true, ms: Date.now() - t0, peakTabMB: peak.tab, peakGpuMB: peak.gpu });
  } catch (e) {
    steps.push({ name, ok: false, ms: Date.now() - t0, peakTabMB: peak.tab, peakGpuMB: peak.gpu, error: e.message });
  }
  console.log(JSON.stringify(steps.at(-1)));
}

await step('open the app (WebKit, iPhone 13), skip the guide', async () => {
  await page.goto(appUrl + '?demo=1', { waitUntil: 'load' });
  await waitText('Skip');
  await click('Skip');
  await waitText('Scan Document');
});
if (args.includes('--no-ocr')) {
  await step('settings: turn off automatic text recognition (measurement only)', async () => {
    await click('Settings');
    for (let i = 0; i < 12 && !(await texts()).some((x) => x.includes('Recognise text automatically')); i++) {
      await page.mouse.move(195, 500);
      await page.mouse.wheel(0, 400);
      await sleep(400);
    }
    await page.evaluate(() => {
      const n = [...document.querySelectorAll('flt-semantics')].find(
        (n) => /Recognise text automatically/.test(n.getAttribute('aria-label') || n.textContent || '') && n.getAttribute('role'),
      );
      n.click();
    });
    await sleep(700);
    await click('Back');
    await waitText('Scan Document');
  });
}
await step('import a photo-sized PDF (4032 x 3024 pt page)', async () => {
  await chooseFile('Import PDF', 'photo_scan.pdf');
  await waitText('Page 1 of 1', 60000);
  await sleep(4000); // render + background OCR
  await click('Back');
  await waitText('Scan Document');
});
await step('scan 3 pages with the demo camera, OCR runs after', async () => {
  await click('Scan Document');
  for (let i = 0; i < 3; i++) {
    await waitText('Keep scan', 30000);
    await click('Keep scan');
    if (i < 2) await click('Next sample page').catch(() => {});
  }
  await sleep(1500);
  await click('Done');
  await waitText('Page 1 of 3', 30000);
  await sleep(8000); // background OCR of 3 pages
});
await step('open Corners and confirm', async () => {
  for (let tries = 0; ; tries++) {
    await click('Corners');
    try {
      await waitText('Use full photo', 8000);
      break;
    } catch (e) {
      if (tries === 4) throw e;
    }
  }
  await click('Confirm');
  await waitText('Page 1 of 3');
  await click('Back');
  await waitText('Scan Document');
});
await step('open Crop and apply', async () => {
  await page.evaluate(() => {
    const n = [...document.querySelectorAll('flt-semantics')].find(
      (n) => /\b3 pages\b/.test(n.getAttribute('aria-label') || n.textContent || '') && n.getAttribute('role'),
    );
    n?.click();
  });
  await waitText('Page 1 of 3');
  for (let tries = 0; ; tries++) {
    await click('Crop');
    try {
      await waitText('Drag the edges or corners of the box', 8000);
      break;
    } catch (e) {
      if (tries === 4) throw e;
    }
  }
  await sleep(2500);
  await click('Apply');
  await waitText('Page 1 of 3');
  await sleep(2000);
  await click('Back');
  await waitText('Scan Document');
});
await step('import a 12 MP iPhone photo', async () => {
  await chooseFile('Import Photos', 'iphone_photo.jpg');
  await waitText('Page 1 of 1', 60000);
  await sleep(6000);
  await click('Back');
  await waitText('Scan Document');
});
await step('the app is still running (no reload, no error screen)', async () => {
  const t = await texts();
  if (!t.some((x) => x.includes('Scan Document'))) throw new Error(`home not shown: ${t.filter(Boolean).slice(0, 12).join(' | ')}`);
  if (!t.some((x) => /\b\d+ pages?\b/.test(x))) throw new Error('documents missing');
});
clearInterval(sampler);
await browser.close();
const failed = steps.filter((s) => !s.ok).length + errors.length;
fs.writeFileSync(
  path.join(here, `../../docs/testing/iphone-flow-${label}.json`),
  JSON.stringify({ label, engine: 'WebKit (Playwright), iPhone 13 emulation', date: new Date().toISOString(), steps, errors }, null, 1),
);
console.log(errors.length ? `errors:\n${errors.join('\n')}` : 'no page errors');
process.exit(failed ? 1 : 0);
