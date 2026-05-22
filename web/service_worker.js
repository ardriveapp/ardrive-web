/**
 * ArDrive Service Worker
 *
 * Cache-first strategy for static assets (JS, WASM, fonts, images).
 * Network-first for HTML (always get fresh app shell).
 * Versioned cache — old caches are cleaned up on activation.
 */

const CACHE_VERSION = 'ardrive-v1';

// Assets to precache on install (critical path)
const PRECACHE_URLS = [
  './',
  './flutter.js',
  './splash/img/splash.svg',
];

// File extensions that should be cached aggressively
const CACHEABLE_EXTENSIONS = [
  '.js',
  '.wasm',
  '.woff2',
  '.woff',
  '.ttf',
  '.png',
  '.svg',
  '.jpg',
  '.json',
  '.css',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  // Clean up old cache versions
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== CACHE_VERSION)
          .map((name) => caches.delete(name))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Only handle same-origin requests
  if (url.origin !== location.origin) return;

  // HTML pages: network-first (always get fresh app shell)
  if (event.request.mode === 'navigate' ||
      url.pathname === '/' ||
      url.pathname.endsWith('.html')) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_VERSION).then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Static assets: cache-first
  const isCacheable = CACHEABLE_EXTENSIONS.some((ext) => url.pathname.endsWith(ext));
  if (isCacheable) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;

        return fetch(event.request).then((response) => {
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_VERSION).then((cache) => cache.put(event.request, clone));
          }
          return response;
        });
      })
    );
    return;
  }

  // Everything else: network only (API calls, etc.)
});
