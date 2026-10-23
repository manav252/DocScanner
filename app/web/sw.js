// DocScanner service worker: makes the web app installable and usable offline.
//   install  : pre-cache every file listed in precache.json (written after each build
//              by tools/pwa_precache.py), so scanning, OCR and PDF import work offline
//   fetch    : the page itself network-first (updates arrive when online), everything
//              else cache-first, filling the cache with anything not pre-cached
//   activate : delete caches of older builds
const VERSION = new URL(self.location).searchParams.get('v') || 'dev';
const CACHE = `docscanner-${VERSION}`;

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      try {
        const list = await (await fetch('precache.json', { cache: 'no-store' })).json();
        // In small batches: a failed file must not abort the whole install.
        for (let i = 0; i < list.length; i += 8) {
          await Promise.all(list.slice(i, i + 8).map((u) => cache.add(new Request(u, { cache: 'reload' })).catch(() => {})));
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
  if (req.mode === 'navigate') {
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(req);
          (await caches.open(CACHE)).put('./', fresh.clone());
          return fresh;
        } catch (_) {
          return (await caches.match('./')) || (await caches.match('index.html')) || Response.error();
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
