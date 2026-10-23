// Shared bits: header/footer, repository link from data/site.json.
const PAGES = [
  ['index.html', 'Home'],
  ['how-it-works.html', 'How it works'],
  ['tests.html', 'Test results'],
  ['features.html', 'Features'],
  ['app/', 'Live demo'],
];

function header() {
  const here = location.pathname.split('/').pop() || 'index.html';
  const links = PAGES.map(([href, label]) => {
    const current = href === here ? ' aria-current="page"' : '';
    return `<li><a href="${href}"${current}>${label}</a></li>`;
  }).join('');
  document.querySelector('header.site').innerHTML = `
    <div class="inner">
      <a class="brand" href="index.html"><img src="img/logo.svg" alt="" width="28" height="28">DocScanner</a>
      <nav aria-label="Main"><ul>${links}</ul></nav>
    </div>`;
}

export async function siteConfig() {
  try {
    const r = await fetch('data/site.json', { cache: 'no-store' });
    return r.ok ? await r.json() : {};
  } catch {
    return {};
  }
}

async function footer() {
  const cfg = await siteConfig();
  const repo = cfg.githubUrl
    ? `<a href="${cfg.githubUrl}">Source code on GitHub</a>`
    : 'Source code: in the project folder (not yet published to GitHub).';
  document.querySelector('footer .inner').innerHTML = `<p>DocScanner: a student project. ${repo}</p>`;
}

header();
footer();
