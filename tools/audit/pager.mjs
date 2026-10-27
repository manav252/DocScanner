// Viewer page buttons in WebKit (iPhone emulation): scan 3 demo pages, then
// press "Next page" / "Previous page" and check which page is shown.
//   node pager.mjs [appUrl]
import { webkit, devices } from 'playwright';

const appUrl = process.argv.find((a) => a.startsWith('http')) ?? 'http://127.0.0.1:8091/app/';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const browser = await webkit.launch();
const page = await (await browser.newContext({ ...devices['iPhone 13'] })).newPage();
const texts = () =>
  page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim()));
async function waitText(needle, timeout = 60000) {
  for (const t0 = Date.now(); Date.now() - t0 < timeout; await sleep(200)) if ((await texts()).some((x) => x.includes(needle))) return;
  throw new Error(`timed out waiting for "${needle}"`);
}
// A real tap at the button's position (not a click on the accessibility node).
async function tap(label) {
  const box = await page.evaluate((label) => {
    const n = [...document.querySelectorAll('flt-semantics')].find((n) => (n.getAttribute('aria-label') || n.textContent || '').trim() === label && n.getAttribute('role') === 'button');
    const r = n?.getBoundingClientRect();
    return r && { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, label);
  if (!box) throw new Error(`no "${label}"`);
  await page.touchscreen.tap(box.x, box.y);
}
async function click(label) {
  const ok = await page.evaluate((label) => {
    const all = [...document.querySelectorAll('flt-semantics')].filter((n) => (n.getAttribute('aria-label') || n.textContent || '').trim() === label);
    const n = all.find((n) => n.getAttribute('role') === 'button') ?? all[0];
    n?.click();
    return !!n;
  }, label);
  if (!ok) throw new Error(`no "${label}"`);
  await sleep(700);
}
const shownImage = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics[role="img"]')].map((n) => n.getAttribute('aria-label')).filter((l) => /^Page \d+ of/.test(l ?? '')));
await page.goto(appUrl + '?demo=1');
await waitText('Skip');
await click('Skip');
await click('Scan Document');
for (let i = 0; i < 3; i++) {
  await waitText('Keep scan', 30000);
  await click('Keep scan');
  if (i < 2) await click('Next sample page').catch(() => {});
}
await sleep(1500);
await click('Done');
await waitText('Page 1 of 3');
await sleep(1500);
const log = [];
for (const b of ['Next page', 'Next page', 'Previous page']) {
  await tap(b);
  await sleep(800);
  log.push({ pressed: b, counter: (await texts()).find((t) => /^Page \d of 3$/.test(t)), imagesInView: await shownImage() });
}
console.log(JSON.stringify(log, null, 1));
await browser.close();
