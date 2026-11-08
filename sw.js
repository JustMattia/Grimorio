// Grimorio PWA Service Worker
const CACHE_NAME = "grimorio-cache-v4";
const STATIC_ASSETS = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./apple-touch-icon.png",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable-512.png",
  "./favicon.png",
  "./fav.png",
  "./favicon.ico"
];

// Install: pre-cache static assets
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch((err) => {
        console.warn("ServiceWorker pre-cache non-bloccante:", err);
      });
    })
  );
  self.skipWaiting();
});

// Activate: clean old caches and take control
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch: Network-First with Cache fallback for app shell, pass-through for APIs
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Bypass per tutte le richieste non-GET e QUALSIASI risorsa esterna (immagini Scryfall su scryfall.io, API Supabase, CDN)
  // Il Service Worker gestisce ESCLUSIVAMENTE la shell locale dell'app per massimizzare la velocità e non intasare Safari
  if (event.request.method !== "GET" || url.origin !== self.location.origin) {
    return;
  }

  // Network-First per HTML e navigazione (garantisce sempre l'ultima versione live)
  if (event.request.mode === "navigate" || event.request.destination === "document") {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => caches.match(event.request).then((res) => res || caches.match("./index.html")))
    );
    return;
  }

  // Stale-While-Revalidate per asset locali (icone, manifest)
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const fetchPromise = fetch(event.request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const copy = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return networkResponse;
        })
        .catch(() => cachedResponse);

      return cachedResponse || fetchPromise;
    })
  );
});

