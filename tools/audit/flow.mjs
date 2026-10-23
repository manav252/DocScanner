// Full user flow in a fresh Chrome profile, recording every console error and
// uncaught exception; then the same app offline (service worker).
//
//   node flow.mjs [appUrl]        default http://localhost:8080/app/
// Writes docs/testing/flow-report.json. Exit code 1 if anything failed.
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));

// The test serves the built app itself (app/build/web at /app/), so "offline" can
// be real: the server is shut down and the page must keep working from its cache.
const webRoot = path.join(here, '../../app/build/web');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.gz': 'application/gzip', '.bin': 'application/octet-stream', '.frag': 'text/plain' };
const server = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (!u.pathname.startsWith('/app/')) { res.writeHead(404).end(); return; }
  let f = path.join(webRoot, decodeURIComponent(u.pathname.slice(5)) || 'index.html');
  if (!f.startsWith(webRoot)) { res.writeHead(403).end(); return; }
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html');
  if (!fs.existsSync(f)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] ?? 'application/octet-stream', 'Cache-Control': 'no-cache' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => server.listen(8097, '127.0.0.1', r));
const appUrl = process.argv[2] ?? 'http://localhost:8097/app/';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const downloads = fs.mkdtempSync(path.join(os.tmpdir(), 'docscanner-flow-'));

const report = { date: new Date().toISOString(), steps: [], consoleErrors: [], pageErrors: [], offline: {} };
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--use-fake-ui-for-media-stream'],
});

const texts = (page) =>
  page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim()));

async function waitText(page, needle, timeout = 30000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if ((await texts(page)).some((t) => t.includes(needle))) return true;
    await sleep(100);
  }
  throw new Error(`timed out waiting for "${needle}"`);
}

async function click(page, label, { exact = true, last = false } = {}) {
  const ok = await page.evaluate(
    (label, exact, last) => {
      const nodes = [...document.querySelectorAll('flt-semantics [role], flt-semantics[role]')].filter((n) =>
        ['button', 'link', 'checkbox', 'radio', 'tab', 'menuitem'].includes(n.getAttribute('role')),
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
  if (!ok) throw new Error(`no control "${label}"`);
  await sleep(700);
}

async function step(name, fn) {
  const t0 = Date.now();
  try {
    await fn();
    report.steps.push({ name, ok: true, ms: Date.now() - t0 });
    console.log('ok  ', name);
  } catch (e) {
    report.steps.push({ name, ok: false, error: String(e.message || e) });
    console.log('FAIL', name, '-', e.message);
  }
}

try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });
  page.on('console', (m) => {
    if (m.type() === 'error') report.consoleErrors.push(m.text());
  });
  page.on('pageerror', (e) => report.pageErrors.push(String(e.message || e)));
  const cdp = await page.createCDPSession();
  await cdp.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads });

  await step('open app (fresh profile), skip the guide', async () => {
    await page.goto(appUrl + '?demo=1', { waitUntil: 'networkidle2' });
    await waitText(page, 'Skip');
    await click(page, 'Skip');
    await waitText(page, 'Scan Document');
  });
  await step('scan 2 pages with the demo camera', async () => {
    await click(page, 'Scan Document');
    await waitText(page, 'Keep scan', 20000);
    await click(page, 'Keep scan');
    await click(page, 'Next sample page');
    await waitText(page, 'Keep scan', 20000);
    await click(page, 'Keep scan');
    await sleep(1500);
    await click(page, 'Done');
    await waitText(page, 'Page 1 of 2', 20000);
  });
  await step('filters: Black & White, then Done', async () => {
    await click(page, 'Filters');
    await waitText(page, 'Black & White');
    await click(page, 'Black & White', { exact: false });
    await sleep(2500);
    await click(page, 'Done', { last: true });
  });
  await step('rotate', async () => {
    await click(page, 'Rotate');
    await sleep(2500);
  });
  await step('markup: pen stroke, Done', async () => {
    await click(page, 'Markup');
    await waitText(page, 'Edit / Markup');
    await click(page, 'Pen');
    await page.mouse.move(300, 300);
    await page.mouse.down();
    for (let i = 1; i < 10; i++) await page.mouse.move(300 + i * 20, 305, { steps: 2 });
    await page.mouse.up();
    await sleep(500);
    await click(page, 'Done');
    await waitText(page, 'Page 1 of 2');
  });
  await step('text recognition (Text view)', async () => {
    await click(page, 'Text');
    const t0 = Date.now();
    while (Date.now() - t0 < 60000) {
      const all = (await texts(page)).join('\n');
      if (all.includes('Copy text') && !all.includes('Recognising')) break;
      await sleep(500);
    }
    await page.keyboard.press('Escape');
    await sleep(800);
  });
  await step('export PDF (download)', async () => {
    await click(page, 'Export');
    await waitText(page, 'Download');
    await click(page, 'Download');
    await waitText(page, 'Saved', 60000);
    await sleep(1000);
    const pdfs = fs.readdirSync(downloads).filter((f) => f.endsWith('.pdf'));
    if (!pdfs.length) throw new Error('no PDF downloaded');
    const head = fs.readFileSync(path.join(downloads, pdfs[0])).subarray(0, 5).toString();
    if (head !== '%PDF-') throw new Error('download is not a PDF');
    report.pdfBytes = fs.statSync(path.join(downloads, pdfs[0])).size;
  });
  await step('delete with Undo, then delete for real', async () => {
    await page.goto(appUrl, { waitUntil: 'domcontentloaded' });
    await waitText(page, 'View Documents');
    await click(page, 'View Documents');
    await waitText(page, '2 pages');
    await click(page, 'Delete');
    await waitText(page, 'Document deleted');
    await click(page, 'Undo');
    await waitText(page, '2 pages');
    await click(page, 'Delete');
    await sleep(6500);
    if ((await texts(page)).some((t) => t.includes('2 pages'))) throw new Error('document still listed');
  });
  await step('settings: export all documents (ZIP)', async () => {
    await page.goto(appUrl + '?demo=1', { waitUntil: 'domcontentloaded' });
    await waitText(page, 'Scan Document');
    // One document so the backup is not empty.
    await click(page, 'Scan Document');
    await waitText(page, 'Keep scan', 20000);
    await click(page, 'Keep scan');
    await sleep(1500);
    await click(page, 'Done');
    await waitText(page, 'Page 1 of 1', 20000);
    await page.goto(appUrl, { waitUntil: 'domcontentloaded' });
    await waitText(page, 'Settings');
    await click(page, 'Settings');
    await waitText(page, 'Export all documents');
    await click(page, 'Export all documents', { exact: false });
    await waitText(page, 'Backup saved', 30000);
    await sleep(1000);
    if (!fs.readdirSync(downloads).some((f) => f.endsWith('.zip'))) throw new Error('no ZIP downloaded');
  });

  // ---- offline ----
  await step('offline copy ready (service worker + pre-cache)', async () => {
    const t0 = Date.now();
    let st;
    while (Date.now() - t0 < 120000) {
      st = await page.evaluate(async () => {
        const reg = await navigator.serviceWorker.getRegistration();
        const keys = await caches.keys();
        let n = 0;
        for (const k of keys) n += (await (await caches.open(k)).keys()).length;
        return { active: !!reg?.active, caches: keys.length, entries: n };
      });
      if (st.active && st.entries >= 40) break;
      await sleep(1000);
    }
    report.offline.cache = st;
    if (!st.active) throw new Error('service worker not active');
  });
  await step('offline: app loads and the demo camera scans (OpenCV from cache)', async () => {
    // Take the site offline for real.
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
    const down = await fetch(appUrl).then(() => false, () => true);
    if (!down) throw new Error('server still reachable');
    await page.goto(appUrl + '?demo=1', { waitUntil: 'domcontentloaded' });
    await waitText(page, 'Scan Document', 30000);
    await click(page, 'Scan Document');
    await waitText(page, 'Keep scan', 30000);
    report.offline.scan = 'ok';
  });
} finally {
  await browser.close();
  server.close();
}

// Expected noise that is not an app error: the browser blocking the real camera in headless mode
// is not triggered (demo camera), so nothing is filtered out.
report.ok = report.steps.every((s) => s.ok) && report.consoleErrors.length === 0 && report.pageErrors.length === 0;
fs.writeFileSync(path.join(here, '../../docs/testing/flow-report.json'), JSON.stringify(report, null, 1));
console.log(`console errors: ${report.consoleErrors.length}, page errors: ${report.pageErrors.length}`);
for (const e of [...report.consoleErrors, ...report.pageErrors]) console.log('  ', e.slice(0, 300));
process.exit(report.ok ? 0 : 1);
