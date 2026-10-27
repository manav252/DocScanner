// Loading the web app like a phone: every request (size, time, failures), page
// and console errors, and when the first screen is usable. Chrome (phone
// viewport, 4G-like network, CPU 4x slower) and WebKit (iPhone emulation).
//   node loadcheck.mjs [url]
import puppeteer from 'puppeteer-core';
import { webkit, devices } from 'playwright';

const url = process.argv.find((a) => a.startsWith('http')) ?? 'https://manav252.github.io/DocScanner/app/';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const usable = async (page) => {
  const t0 = Date.now();
  while (Date.now() - t0 < 60000) {
    const ok = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].some((n) => /Skip|Scan Document/.test(n.getAttribute('aria-label') || n.textContent || '')));
    if (ok) return Date.now() - t0;
    await sleep(100);
  }
  return null;
};

// Chrome
{
  const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  const page = await browser.newPage();
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 3, isMobile: true });
  const cdp = await page.createCDPSession();
  await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 60, downloadThroughput: (9e6 / 8), uploadThroughput: (3e6 / 8) });
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  const reqs = [], problems = [];
  page.on('requestfinished', async (r) => {
    const res = r.response();
    reqs.push({ url: r.url().replace(url, ''), status: res?.status(), kb: Math.round(((await res?.buffer().catch(() => null))?.length ?? 0) / 1024) });
  });
  page.on('requestfailed', (r) => problems.push(`failed: ${r.url()} ${r.failure()?.errorText}`));
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('console', (m) => m.type() === 'error' && problems.push(`console: ${m.text().slice(0, 200)}`));
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  const ms = await usable(page);
  await sleep(2000);
  console.log(`Chrome (4G-like, CPU 4x): usable after ${ms === null ? 'NEVER' : ms + Date.now() * 0 + ' ms (since HTML)'}; total ${Date.now() - t0} ms`);
  const big = reqs.filter((r) => r.kb > 50).sort((a, b) => b.kb - a.kb);
  console.log(`requests: ${reqs.length}, ${reqs.reduce((s, r) => s + r.kb, 0)} KB; large:`, big.map((r) => `${r.url} ${r.kb}KB`).join(', '));
  console.log('bad status:', reqs.filter((r) => r.status >= 400).map((r) => `${r.status} ${r.url}`));
  console.log('problems:', problems);
  await browser.close();
}
// WebKit
{
  const browser = await webkit.launch();
  const page = await (await browser.newContext({ ...devices['iPhone 13'] })).newPage();
  const problems = [], bad = [];
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('console', (m) => m.type() === 'error' && problems.push(`console: ${m.text().slice(0, 200)}`));
  page.on('requestfailed', (r) => problems.push(`failed: ${r.url()} ${r.failure()?.errorText}`));
  page.on('response', (r) => r.status() >= 400 && bad.push(`${r.status()} ${r.url()}`));
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  const ms = await usable(page);
  await sleep(2000);
  console.log(`WebKit (iPhone 13): usable after ${ms === null ? 'NEVER' : ms + ' ms'}`);
  console.log('bad status:', bad, 'problems:', problems);
  await browser.close();
}
