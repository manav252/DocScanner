// Screenshots of the real web app for the showcase website (website/img/screens/).
// Drives the app through its accessibility tree with the demo camera, so the
// pages shown are the built-in sample documents (labelled as such on the site).
//
//   node screenshots.mjs [appUrl]      default http://localhost:8080/app/
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const appUrl = process.argv[2] ?? 'http://localhost:8080/app/';
const out = path.join(here, '../../website/img/screens');
fs.mkdirSync(out, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});

async function click(page, label, { exact = false, wait = 2000 } = {}) {
  const ok = await page.evaluate(
    (label, exact) => {
      const nodes = [...document.querySelectorAll('flt-semantics [role], flt-semantics[role]')].filter((n) =>
        ['button', 'tab', 'checkbox', 'radio', 'switch', 'menuitem'].includes(n.getAttribute('role')));
      const text = (n) => (n.getAttribute('aria-label') || n.textContent || '').trim();
      const hit = nodes.find((n) => (exact ? text(n) === label : text(n).startsWith(label)));
      hit?.click();
      return !!hit;
    },
    label,
    exact,
  );
  if (!ok) throw new Error(`no button "${label}"`);
  await sleep(wait);
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(out, `${name}.png`) });
  console.log('saved', name);
}

try {
  const page = await browser.newPage();
  await page.setViewport({ width: 412, height: 880, deviceScaleFactor: 2 });
  await page.goto(appUrl + '?demo=1', { waitUntil: 'networkidle2' });
  await page.waitForSelector('flt-semantics-host flt-semantics', { timeout: 30000 });
  await sleep(1500);
  await shot(page, 'guide');
  await click(page, 'Skip', { exact: true });
  await shot(page, 'home-empty');

  // Scan two sample pages with the demo camera (auto-capture).
  await click(page, 'Scan Document', { wait: 6000 });
  await shot(page, 'review-corners');
  await click(page, 'Keep scan', { wait: 2500 });
  await click(page, 'Next sample page', { wait: 6000 });
  await click(page, 'Keep scan', { wait: 2500 });
  await shot(page, 'scanner');
  await click(page, 'Done', { exact: true, wait: 4000 });
  await shot(page, 'editor');

  await click(page, 'Filters', { exact: true, wait: 5000 });
  await shot(page, 'filters');
  await click(page, 'Done', { exact: true, wait: 1500 });

  await click(page, 'Markup', { exact: true, wait: 3000 });
  await click(page, 'Pen', { exact: true, wait: 500 });
  const canvas = await page.evaluate(() => {
    const r = document.querySelector('flt-glass-pane, flutter-view').getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width };
  });
  // Underline the heading of the page shown in the top half.
  await page.mouse.move(canvas.x + 110, canvas.y + 150);
  await page.mouse.down();
  for (let i = 1; i <= 12; i++) await page.mouse.move(canvas.x + 110 + i * 15, canvas.y + 152, { steps: 2 });
  await page.mouse.up();
  await sleep(800);
  await shot(page, 'markup');
  await click(page, 'Done', { exact: true, wait: 2500 });

  await click(page, 'Export', { exact: true, wait: 2500 });
  await shot(page, 'export');
  await page.keyboard.press('Escape');
  await sleep(1500);

  // Desktop layout of the editor.
  await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 1 });
  await sleep(2500);
  await shot(page, 'editor-desktop');
} finally {
  await browser.close();
}
