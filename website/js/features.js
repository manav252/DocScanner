import { siteConfig } from './site.js';

const el = document.getElementById('repo');
const cfg = await siteConfig();
el.innerHTML = cfg.githubUrl
  ? `<p><a class="btn primary" href="${cfg.githubUrl}">View the code on GitHub</a></p>`
  : `<p>The repository has not been published to GitHub yet. When it is, put its address in
     <code>website/data/site.json</code> (<code>"githubUrl"</code>) and the link appears here and in the footer.
     The code is in the project folder; see the README for how to run it.</p>`;
