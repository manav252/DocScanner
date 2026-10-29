// DocScanner service worker: makes the web app installable and usable offline.
//   install  : pre-cache every file listed in precache.json (written after each build
//              by tools/pwa_precache.py), so scanning, OCR and PDF import work offline.
//              Entries carry a content hash: unchanged files are copied from the
//              previous version's cache, so an update downloads only what changed.
//   fetch    : the page itself and flutter_bootstrap.js (which names the build, so
//              registers the next build's worker) network-first, but from the cache
//              if the network has not answered in 4 s (a slow or stalled mobile
//              connection must not leave a blank page); everything else cache-first,
//              filling the cache with anything not pre-cached
//   activate : delete caches of older builds
const VERSION = new URL(self.location).searchParams.get('v') || 'dev';
// "-2": this worker's own cache, apart from the one an older worker filled
// (which served flutter_bootstrap.js from its cache, so never learnt of a new build).
const CACHE = `docscanner-${VERSION}-2`;
// Fetched network-first, like the page: they say which build is current.
const FRESH = new Set(['flutter_bootstrap.js', 'version.json']);

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      try {
        const list = await (await fetch('precache.json', { cache: 'no-store' })).json();
        // Unchanged files (same hash) from an older version's cache; the rest
        // downloaded 3 at a time (gentle on a phone), a failed file not
        // aborting the install.
        const get = async (u) => {
          const old = await caches.match(u);
          if (old) return cache.put(u, old);
          return cache.add(new Request(u, { cache: 'reload' }));
        };
        for (let i = 0; i < list.length; i += 3) {
          await Promise.all(list.slice(i, i + 3).map((u) => get(u).catch(() => {})));
        }
      } catch (_) {
        // No list (development build): files are cached as they are used.
      }
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const k of await caches.keys()) if (k.startsWith('docscanner-') && k !== CACHE) await caches.delete(k);
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return; // API calls go to the network
  if (!url.pathname.startsWith(new URL('./', self.location).pathname)) return; // outside the app (website)
  const name = url.pathname.slice(new URL('./', self.location).pathname.length);
  if (req.mode === 'navigate' || FRESH.has(name)) {
    const key = req.mode === 'navigate' ? './' : name;
    event.respondWith(
      (async () => {
        const cache = await caches.open(CACHE);
        const cached = async () =>
          req.mode === 'navigate'
            ? (await cache.match('./')) || (await cache.match('index.html', { ignoreSearch: true }))
            : await cache.match(name, { ignoreSearch: true });
        const network = fetch(req, { cache: 'no-cache' }).then(async (fresh) => {
          if (fresh.ok) await cache.put(key, fresh.clone());
          return fresh;
        });
        const slow = new Promise((resolve) => setTimeout(() => resolve('slow'), 4000));
        try {
          const first = await Promise.race([network, slow]);
          if (first !== 'slow') return first;
          return (await cached()) || (await network);
        } catch (_) {
          return (await cached()) || Response.error();
        }
      })(),
    );
    return;
  }
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const hit = (await cache.match(req)) || (await cache.match(req, { ignoreSearch: true }));
      if (hit) return hit;
      const res = await fetch(req);
      if (res.ok && res.type === 'basic') cache.put(req, res.clone());
      return res;
    })(),
  );
});
