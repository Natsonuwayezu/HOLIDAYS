// sw.js - Service Worker for ECOLE LA FONTAINE
// FIXED: was caching '/manifest.json' (an orphaned, unused file with placeholder
// icon paths that don't exist) instead of '/site.webmanifest' (the file actually
// linked in the HTML's <link rel="manifest">). Also bumped the cache version so
// everyone picks up this fix instead of serving the old broken cache list.
const CACHE_NAME = 'ecole-La-fontaine-v8';
const urlsToCache = [
    '/',
    '/index.html',           // <-- CONFIRM: replace with your actual deployed filename if different
    '/site.webmanifest'
];

self.addEventListener('install', event => {
    self.skipWaiting();
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(urlsToCache))
    );
});

self.addEventListener('fetch', event => {
    event.respondWith(
        caches.match(event.request)
            .then(response => response || fetch(event.request))
    );
});

self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(keys => {
            return Promise.all(
                keys.filter(key => key !== CACHE_NAME)
                    .map(key => caches.delete(key))
            );
        }).then(() => self.clients.claim())
    );
});
