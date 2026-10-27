// Live scanner: how busy the page's main thread is while the camera runs and
// pages are detected (headless Chrome, fake camera = the real web camera code
// path, CPU throttled). Frame times cannot be used: headless Chrome paces
// frames to the 30 fps fake video. Profiles 5 s and reports busy % (not idle)
// and the top functions, plus the CPU used by the page and its workers
// together (unthrottled, before the profile).
//
//   node scanner_profile.mjs [appUrl] [--label name] [--cpu 6] [--runs 3]
// Writes docs/testing/scanner-profile-<label>.json.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
import puppeteer from 'puppeteer-core';

// Total CPU seconds used so far by Chrome's renderer processes (the page and
// its workers: the heat a phone feels), from ps.
function rendererCpuSeconds() {
  return execSync('ps -axo time=,command=')
    .toString()
    .split('\n')
    .filter((r) => r.includes('Renderer') && r.includes('Chrome'))
    .reduce((sum, r) => {
      const [t] = r.trim().split(/\s+/);
      const parts = t.split(':').map(Number); // [h:]m:s.cs
      return sum + parts.reduce((a, b) => a * 60 + b, 0);
    }, 0);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (n, d) => (args.includes(`--${n}`) ? args[args.indexOf(`--${n}`) + 1] : d);
const appUrl = args.find((a) => a.startsWith('http')) ?? 'http://127.0.0.1:8091/app/';
const label = opt('label', 'run');
const cpu = Number(opt('cpu', 6));
const runs = Number(opt('runs', 3));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'],
});
const results = [];
try {
  for (let run = 0; run < runs; run++) {
    const ctx = await browser.createBrowserContext();
    const p = await ctx.newPage();
    await p.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true });
    await p.goto(appUrl + (args.includes('--old-grab') ? '?oldgrab=1' : ''), { waitUntil: 'networkidle2' });
    const click = (l) =>
      p.evaluate((l) => {
        const a = [...document.querySelectorAll('flt-semantics')].filter((n) => (n.getAttribute('aria-label') || n.textContent || '').trim() === l);
        (a.find((n) => n.getAttribute('role') === 'button') ?? a[0])?.click();
      }, l);
    const texts = () =>
      p.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim()));
    for (let i = 0; i < 80 && !(await texts()).includes('Skip'); i++) await sleep(250);
    await click('Skip');
    await sleep(1500);
    await click('Scan Document');
    // The fake camera shows a still test pattern, which would be captured after
    // 4 s of stillness: turn auto-capture off to keep measuring the live view.
    for (let i = 0; i < 40 && !(await texts()).some((t) => /Auto capture/.test(t)); i++) await sleep(100);
    await p.evaluate(() => {
      const n = [...document.querySelectorAll('flt-semantics')].find(
        (n) => /Auto capture/.test(n.getAttribute('aria-label') || n.textContent || '') && n.getAttribute('role'),
      );
      n?.click();
    });
    await sleep(6000);
    const shown = await texts();
    if (!shown.some((t) => /Auto capture/.test(t))) throw new Error(`scanner not open: ${shown.filter(Boolean).slice(0, 10).join(' | ')}`);
    const cpu0 = rendererCpuSeconds(), wall0 = Date.now();
    await sleep(5000);
    // All cores: 100 % = one core fully busy for the whole time (no throttling).
    const cpuPercent = +((100 * (rendererCpuSeconds() - cpu0)) / ((Date.now() - wall0) / 1000)).toFixed(0);
    const cdp = await p.createCDPSession();
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: cpu });
    await cdp.send('Profiler.enable');
    await cdp.send('Profiler.setSamplingInterval', { interval: 200 });
    await cdp.send('Profiler.start');
    await sleep(5000);
    const { profile } = await cdp.send('Profiler.stop');
    const byId = new Map(profile.nodes.map((n) => [n.id, n]));
    const self = new Map();
    profile.samples.forEach((id, i) => {
      const n = byId.get(id);
      const k = n.callFrame.functionName || '(anonymous)';
      self.set(k, (self.get(k) || 0) + (profile.timeDeltas[i] || 0));
    });
    const total = [...self.values()].reduce((a, b) => a + b, 0);
    const pct = (k) => +((100 * (self.get(k) || 0)) / total).toFixed(1);
    const top = [...self.entries()]
      .filter(([k]) => !['(idle)', '(program)'].includes(k))
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([k, us]) => `${k} ${((100 * us) / total).toFixed(1)}%`);
    results.push({ run, cpuPercent, busyPercent: +(100 - pct('(idle)')).toFixed(1), drawImagePercent: pct('drawImage'), top });
    console.log(JSON.stringify(results.at(-1)));
    await ctx.close();
  }
} finally {
  await browser.close();
}
fs.writeFileSync(
  path.join(here, `../../docs/testing/scanner-profile-${label}.json`),
  JSON.stringify({ label, cpuSlowdown: cpu, camera: 'Chrome fake camera', runs: results }, null, 1),
);
