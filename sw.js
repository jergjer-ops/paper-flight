/* Paper Flight — offline app shell.
 * Registered only on the top-level GitHub Pages site (never inside the
 * GamePix iframe or other embeds). Documents are network-first so Telegram
 * WebView cannot remain pinned to an old game build after a normal reload. */
/* Bump this name on every release so the new version never serves stale
 * assets from a previous deployment (activate() deletes all other caches). */
const CACHE = 'paper-flight-v8';
const ASSETS = [
  './',
  './index.html',
  './mobile.css',
  './mobile-adapter.js',
  './yt-playables-adapter.js',
  './crazygames-adapter.js',
  './gamedistribution-adapter.js',
  './public-config.js',
  './privacy.html',
  './og-image.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(ASSETS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  // Never cache cross-origin requests (Supabase API, GamePix SDK, CDN fonts).
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const isDocument = request.mode === 'navigate'
    || url.pathname.endsWith('/')
    || url.pathname.endsWith('/index.html');

  if (isDocument) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches
              .open(CACHE)
              .then((cache) => cache.put('./index.html', copy))
              .catch(() => {});
          }
          return response;
        })
        .catch(() => caches.match('./index.html')),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches
            .open(CACHE)
            .then((cache) => cache.put(request, copy))
            .catch(() => {});
          return response;
        })
        .catch(() => caches.match('./index.html'));
    }),
  );
});
