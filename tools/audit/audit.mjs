// Accessibility audit: axe-core on each screen of the web app (and the
// showcase website), plus Lighthouse's accessibility score for each page.
// Uses the installed Google Chrome. Writes docs/testing/a11y-report.json.
//
//   node audit.mjs [appUrl] [siteUrl]
//   defaults: http://localhost:8090/  http://localhost:8080/
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';
import lighthouse from 'lighthouse';

const here = path.dirname(fileURLToPath(import.meta.url));
const appUrl = process.argv[2] ?? 'http://localhost:8090/';
const siteUrl = process.argv[3] ?? 'http://localhost:8080/';
const chromePath = process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const axeSource = fs.readFileSync(path.join(here, 'node_modules/axe-core/axe.min.js'), 'utf8');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function runAxe(page) {
  await page.evaluate(axeSource);
  return page.evaluate(async () => {
    // WCAG 2.0/2.1/2.2 A and AA rules.
    const r = await window.axe.run(document, { runOnly: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'] });
    return {
      violations: r.violations.map((v) => ({
        id: v.id,
        impact: v.impact,
        help: v.help,
        nodes: v.nodes.slice(0, 5).map((n) => n.target.join(' ')),
      })),
      passes: r.passes.length,
    };
  });
}

/// Flutter web: wait until the accessibility tree is in the DOM.
async function waitForFlutter(page) {
  await page.waitForSelector('flt-semantics-host flt-semantics', { timeout: 30000 });
  await sleep(1500);
}

/// Click a Flutter control by its visible label (via the semantics DOM).
async function clickLabel(page, label) {
  const ok = await page.evaluate((label) => {
    const nodes = [...document.querySelectorAll('flt-semantics [role="button"], flt-semantics button, flt-semantics[role="button"]')];
    const hit = nodes.find((n) => (n.getAttribute('aria-label') ?? n.textContent ?? '').trim().startsWith(label));
    if (!hit) return false;
    hit.click();
    return true;
  }, label);
  if (!ok) throw new Error(`no control labelled "${label}"`);
  await sleep(2500);
}

async function lighthouseScore(port, url) {
  const r = await lighthouse(url, { port, output: 'json', onlyCategories: ['accessibility'], logLevel: 'error' });
  const cat = r.lhr.categories.accessibility;
  const failed = Object.values(r.lhr.audits)
    .filter((a) => a.score === 0 && a.scoreDisplayMode === 'binary')
    .map((a) => ({ id: a.id, title: a.title }));
  return { score: Math.round(cat.score * 100), failed };
}

const browser = await puppeteer.launch({
  executablePath: chromePath,
  headless: true,
  args: ['--remote-debugging-port=9333', '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'],
});
const report = { date: new Date().toISOString(), app: {}, site: {} };
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });

  // ---- Flutter web app ----
  const appScreens = [
    ['Home', []],
    ['Documents', ['View Documents']],
    ['Settings', ['Settings']],
  ];
  for (const [name, clicks] of appScreens) {
    await page.goto(appUrl, { waitUntil: 'networkidle2' });
    await waitForFlutter(page);
    // First run shows the 3-step guide: skip it.
    await page.evaluate(() => {
      const skip = [...document.querySelectorAll('flt-semantics [role="button"]')].find((n) => n.textContent.trim() === 'Skip');
      skip?.click();
    });
    await sleep(1500);
    for (const c of clicks) await clickLabel(page, c);
    report.app[name] = await runAxe(page);
    console.log(`app ${name}: ${report.app[name].violations.length} axe violations`);
  }
  report.app.lighthouse = await lighthouseScore(9333, appUrl);
  console.log(`app Lighthouse accessibility: ${report.app.lighthouse.score}`);

  // ---- Showcase website (if running) ----
  const siteUp = await fetch(siteUrl).then((r) => r.ok).catch(() => false);
  if (siteUp) {
    for (const p of ['', 'how-it-works.html', 'tests.html', 'features.html']) {
      const url = new URL(p, siteUrl).href;
      await page.goto(url, { waitUntil: 'networkidle2' });
      const axe = await runAxe(page);
      const lh = await lighthouseScore(9333, url);
      report.site[p || 'index.html'] = { ...axe, lighthouse: lh };
      console.log(`site ${p || 'index.html'}: ${axe.violations.length} axe violations, Lighthouse ${lh.score}`);
    }
  } else {
    console.log(`site not running at ${siteUrl}; skipped`);
  }
} finally {
  await browser.close();
}

const out = path.join(here, '../../docs/testing/a11y-report.json');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(report, null, 2));
console.log(`wrote ${path.relative(process.cwd(), out)}`);
