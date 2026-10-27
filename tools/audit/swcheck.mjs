// The offline copy (service worker, app/web/sw.js) in Chrome:
//  1. first visit: how many files the offline copy holds;
//  2. an update (new version, same files): how many files are downloaded again;
//  3. a stalled network (8 s per request): how long until the app shows.
//   node swcheck.mjs [appUrl]
import puppeteer from 'puppeteer-core';

const url = process.argv.find((a) => a.startsWith('http')) ?? 'http://127.0.0.1:8093/app/';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
const swRequests = [];
const swSessions = [];
browser.on('targetcreated', async (t) => {
  if (t.type() !== 'service_worker') return;
  const s = await t.createCDPSession();
  swSessions.push(s);
  await s.send('Network.enable');
  s.on('Network.requestWillBeSent', (e) => swRequests.push(e.request.url));
});
const page = await browser.newPage();
const shown = async () => {
  const t0 = Date.now();
  while (Date.now() - t0 < 60000) {
    if (await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].some((n) => /Skip|Scan Document/.test(n.getAttribute('aria-label') || n.textContent || '')))) return Date.now() - t0;
    await sleep(100);
  }
  return null;
};
await page.goto(url);
console.log('first visit: app shown after', await shown(), 'ms');
const cached = () =>
  page.evaluate(async () => {
    const out = {};
    for (const k of await caches.keys()) out[k] = (await (await caches.open(k)).keys()).length;
    return out;
  });
for (let i = 0; i < 120; i++) {
  const c = await cached();
  if (Object.values(c).some((n) => n >= 40)) break;
  await sleep(1000);
}
await sleep(2000);
console.log('offline copy:', await cached(), '; downloaded by the worker:', swRequests.length);
swRequests.length = 0;
await page.evaluate(async () => {
  const reg = await navigator.serviceWorker.register('sw.js?v=update-test');
  await new Promise((r) => {
    const w = reg.installing || reg.waiting;
    if (!w) return r();
    w.addEventListener('statechange', () => w.state === 'activated' && r());
  });
});
await sleep(1000);
console.log('after an update:', await cached(), '; downloaded again:', swRequests.length, swRequests.map((u) => u.replace(url, '')).slice(0, 8));
// Stalled network for the page and the worker.
const slow = { offline: false, latency: 8000, downloadThroughput: -1, uploadThroughput: -1 };
const pageCdp = await page.createCDPSession();
await pageCdp.send('Network.enable');
await pageCdp.send('Network.emulateNetworkConditions', slow);
for (const s of swSessions) await s.send('Network.emulateNetworkConditions', slow).catch(() => {});
const t0 = Date.now();
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 }).catch((e) => console.log('goto:', e.message));
const html = Date.now() - t0;
await shown();
console.log(`stalled network (8 s per request): page arrived after ${html} ms, app shown after ${Date.now() - t0} ms`);
await browser.close();
