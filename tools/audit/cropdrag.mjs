// Crop screen smoothness in headless Chrome, slowed down like a low-end phone.
//
//   node cropdrag.mjs [appUrl] [--label before|after] [--runs 3] [--cpu 4]
//
// Imports a 3000x4000 photo (the size of a 12 MP phone photo), opens Corners,
// then drags a corner handle for ~2 s with the CPU throttled (--cpu 4 = 4x
// slower) at a phone viewport (390x844, 2x pixels). Records every frame
// interval (requestAnimationFrame) and long tasks during the drag.
// Results are written to docs/testing/cropdrag-<label>.json.
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
const appUrl = args.find((a) => a.startsWith('http')) ?? 'http://127.0.0.1:8091/app/';
const label = opt('label', 'run');
const runs = Number(opt('runs', 3));
const cpu = Number(opt('cpu', 4));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const W = 3000, H = 4000;

const texts = (page) =>
  page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim()));
async function waitText(page, needle, timeout = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if ((await texts(page)).some((t) => t.includes(needle))) return;
    await sleep(100);
  }
  throw new Error(`timed out waiting for "${needle}"`);
}
async function click(page, label) {
  const ok = await page.evaluate((label) => {
    const n = [...document.querySelectorAll('flt-semantics[role=button], flt-semantics [role=button]')].find(
      (n) => (n.getAttribute('aria-label') || n.textContent || '').trim() === label,
    );
    n?.click();
    return !!n;
  }, label);
  if (!ok) throw new Error(`no button "${label}"`);
  await sleep(600);
}

const stats = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const q = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
  return { frames: s.length, p50: +q(0.5).toFixed(1), p95: +q(0.95).toFixed(1), max: +s.at(-1).toFixed(1), over33ms: s.filter((x) => x > 33.4).length };
};

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const results = [];
try {
  for (let run = 0; run < runs; run++) {
    const ctx = await browser.createBrowserContext();
    const page = await ctx.newPage();
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: process.env.MOBILE !== '0', hasTouch: false });
    await page.goto(appUrl, { waitUntil: 'networkidle2' });
    await waitText(page, 'Skip');
    await click(page, 'Skip');
    await waitText(page, 'Import Photos');
    // A photo-sized JPEG (paper on a textured desk), fed to the file picker.
    await page.evaluate((W, H) => {
      const c = document.createElement('canvas');
      c.width = W;
      c.height = H;
      const g = c.getContext('2d');
      g.fillStyle = '#7a5c3e';
      g.fillRect(0, 0, W, H);
      for (let i = 0; i < 4000; i++) {
        g.fillStyle = `rgba(${60 + Math.random() * 80},${40 + Math.random() * 50},20,0.3)`;
        g.fillRect(Math.random() * W, Math.random() * H, 40, 3);
      }
      g.fillStyle = '#f4f1ea';
      g.beginPath();
      g.moveTo(420, 520); g.lineTo(2600, 400); g.lineTo(2700, 3600); g.lineTo(300, 3500);
      g.fill();
      g.fillStyle = '#222';
      g.font = '90px sans-serif';
      for (let y = 800; y < 3200; y += 160) g.fillText('Lorem ipsum dolor sit amet', 600, y);
      window.__photo = new Promise((r) => c.toBlob((b) => r(new File([b], 'photo.jpg', { type: 'image/jpeg' })), 'image/jpeg', 0.9));
      const orig = HTMLInputElement.prototype.click;
      HTMLInputElement.prototype.click = function () {
        if (this.type !== 'file') return orig.call(this);
        window.__photo.then((f) => {
          const dt = new DataTransfer();
          dt.items.add(f);
          this.files = dt.files;
          this.dispatchEvent(new Event('change'));
        });
      };
    }, W, H);
    await click(page, 'Import Photos');
    await waitText(page, 'Page 1 of 1');
    await click(page, 'Corners');
    await waitText(page, 'Use full photo');
    await click(page, 'Use full photo');
    await sleep(1500);
    // Corners are now the photo's corners: the image fitted into the editor.
    const box = await page.evaluate(() => {
      const nodes = [...document.querySelectorAll('flt-semantics')];
      const n = nodes.find((n) => (n.getAttribute('aria-label') || n.textContent || '').trim().startsWith('Page corners'));
      if (!n) throw new Error('no editor; labels: ' + nodes.map((n) => (n.getAttribute('aria-label') || '').slice(0, 40)).filter(Boolean).join(' | '));
      const r = n.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height };
    });
    const s = Math.min(box.w / W, box.h / H);
    // Bottom-right corner: away from the left-edge "swipe back" zone (see --corner).
    const corner = opt('corner', 'br');
    const at =
      corner === 'tl'
        ? { x: box.x + (box.w - W * s) / 2 + 2, y: box.y + (box.h - H * s) / 2 + 2, dir: 1 }
        : { x: box.x + (box.w + W * s) / 2 - 2, y: box.y + (box.h + H * s) / 2 - 2, dir: -1 };

    const cdp = await page.createCDPSession();
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: cpu });
    await page.evaluate(() => {
      window.__frames = [];
      window.__long = [];
      new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__long.push(e.duration))).observe({ type: 'longtask' });
      let last = performance.now();
      const tick = (t) => {
        window.__frames.push(t - last);
        last = t;
        if (window.__rec) requestAnimationFrame(tick);
      };
      window.__rec = true;
      requestAnimationFrame(tick);
    });
    // Pointer events with the button held on every move (what a finger drag
    // sends); CDP mouse drags do not reach Flutter's pan recogniser reliably.
    await page.evaluate(async (x0, y0, dir) => {
      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
      const target = document.elementFromPoint(x0, y0);
      const ev = (type, x, y, buttons) =>
        target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y,
          pointerId: 1, pointerType: 'mouse', button: type === 'pointermove' ? -1 : 0, buttons, isPrimary: true }));
      ev('pointerdown', x0, y0, 1);
      let x = x0, y = y0;
      for (let i = 1; i <= 120; i++) {
        // Out along a diagonal, then halfway back: ~2 s of dragging.
        const k = i <= 80 ? i : 160 - i;
        x = x0 + dir * k * 2;
        y = y0 + dir * k * 2.5;
        ev('pointermove', x, y, 1);
        await sleep(16);
      }
      ev('pointerup', x, y, 0);
    }, at.x, at.y, at.dir);
    await sleep(300);
    const r = await page.evaluate(() => {
      window.__rec = false;
      return { frames: window.__frames.slice(2), long: window.__long };
    });
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    // "Use full photo" is disabled while the corners are the full photo: enabled = the drag moved a corner.
    const moved = await page.evaluate(() => {
      const n = [...document.querySelectorAll('flt-semantics')].find((n) => (n.getAttribute('aria-label') || n.textContent || '').trim() === 'Use full photo');
      return n?.getAttribute('aria-disabled') !== 'true';
    });
    if (!moved) throw new Error('the drag did not move a corner');
    results.push({ run, ...stats(r.frames), longTasks: r.long.length, longestTask: Math.round(Math.max(0, ...r.long)) });
    console.log(JSON.stringify(results.at(-1)));
    await ctx.close();
  }
} finally {
  await browser.close();
}
const out = { label, date: new Date().toISOString(), cpuSlowdown: cpu, photo: `${W}x${H}`, viewport: '390x844 @2x', runs: results };
fs.writeFileSync(path.join(here, `../../docs/testing/cropdrag-${label}.json`), JSON.stringify(out, null, 1));
