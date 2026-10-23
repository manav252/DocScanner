// Renders data/test-results.json and data/a11y-report.json (both written by tools/).
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const cls = { passed: 'pass', failed: 'fail', skipped: 'skip-s' };
const word = { passed: 'Passed', failed: 'Failed', skipped: 'Skipped' };

async function load(url) {
  const r = await fetch(url, { cache: 'no-store' });
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  return r.json();
}

function suiteBlock(s) {
  if (s.status !== 'run') {
    return `<div class="card"><h3>${esc(s.title)}</h3><p><span class="status-tag skip-s">Not run</span> ${esc(s.reason)}</p></div>`;
  }
  const byFile = new Map();
  for (const t of s.tests) {
    if (!byFile.has(t.file)) byFile.set(t.file, []);
    byFile.get(t.file).push(t);
  }
  const rows = [...byFile.entries()]
    .map(([file, tests]) => tests.map((t, i) => `<tr>${i === 0 ? `<td rowspan="${tests.length}"><code>${esc(file)}</code></td>` : ''}<td>${esc(t.name)}</td><td class="${cls[t.status]}">${word[t.status]}</td></tr>`).join(''))
    .join('');
  const state = s.failed ? `<span class="status-tag fail">${s.failed} failed</span>` : '<span class="status-tag pass">All passed</span>';
  return `<div class="card" style="margin-top:12px">
    <h3>${esc(s.title)}</h3>
    <p>${state} · <span class="pass">${s.passed} passed</span> · <span class="fail">${s.failed} failed</span> · <span class="skip-s">${s.skipped} skipped</span> · <code>${esc(s.command)}</code></p>
    <details><summary>Show all ${s.tests.length} tests</summary>
      <div class="table-wrap"><table><caption class="vh">${esc(s.title)}: every test</caption>
        <thead><tr><th scope="col">File</th><th scope="col">Test</th><th scope="col">Result</th></tr></thead>
        <tbody>${rows}</tbody></table></div>
    </details></div>`;
}

async function results() {
  const el = document.getElementById('results');
  try {
    const r = await load('data/test-results.json');
    const when = new Date(r.generatedAt).toLocaleString();
    const t = r.totals;
    el.innerHTML = `
      <p>Last run: <strong>${esc(when)}</strong>${r.commit ? ` · commit <code>${esc(r.commit)}</code>` : ''}</p>
      <div class="totals">
        <div class="card"><span class="big pass">${t.passed}</span>passed</div>
        <div class="card"><span class="big ${t.failed ? 'fail' : ''}">${t.failed}</span>failed</div>
        <div class="card"><span class="big">${t.skipped}</span>skipped</div>
        <div class="card"><span class="big">${r.suites.filter((s) => s.status === 'run').length} / ${r.suites.length}</span>suites run</div>
      </div>
      <h2>Suites</h2>
      ${r.suites.map(suiteBlock).join('')}`;
  } catch (e) {
    el.innerHTML = `<p class="note">No test results yet (${esc(e.message)}). Run <code>tools/run_tests.sh</code>.</p>`;
  }
}

async function a11y() {
  const el = document.getElementById('a11y');
  try {
    const r = await load('data/a11y-report.json');
    const rows = Object.entries(r.app)
      .filter(([k]) => k !== 'lighthouse')
      .map(([k, v]) => `<tr><td>Web app: ${esc(k)}</td><td class="${v.violations.length ? 'fail' : 'pass'}">${v.violations.length}</td><td>${v.passes}</td></tr>`)
      .concat(Object.entries(r.site ?? {}).map(([k, v]) => `<tr><td>Website: ${esc(k)}</td><td class="${v.violations.length ? 'fail' : 'pass'}">${v.violations.length}</td><td>${v.passes}</td></tr>`))
      .join('');
    const lh = [`Web app ${r.app.lighthouse?.score ?? '?'}`, ...Object.entries(r.site ?? {}).map(([k, v]) => `${k} ${v.lighthouse?.score ?? '?'}`)].join(' · ');
    el.innerHTML = `<p>axe-core (WCAG 2.2 A/AA rules) and Lighthouse, ${esc(new Date(r.date).toLocaleString())}.</p>
      <div class="table-wrap"><table><thead><tr><th scope="col">Page</th><th scope="col">axe violations</th><th scope="col">axe rules passed</th></tr></thead><tbody>${rows}</tbody></table></div>
      <p>Lighthouse accessibility scores: ${esc(lh)}</p>
      <p class="muted">The app draws its text on a canvas, so axe cannot measure its colour contrast; contrast, tap-target size and labels are checked by Flutter’s accessibility guideline tests (in the Flutter suite above).</p>`;
  } catch (e) {
    el.innerHTML = `<p class="note">No audit yet (${esc(e.message)}). Run <code>npm run audit</code> in <code>tools/audit</code>.</p>`;
  }
}

results();
a11y();
