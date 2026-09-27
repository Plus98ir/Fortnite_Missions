/* Offline support: app shell cached on install, mission data network-first
 * (falls back to the last copy), icons/art cache-first, fonts cache-first. */
var VERSION = "fnapp-2.0.0";
var SHELL = ["./", "index.html", "app.css", "app.js", "manifest.webmanifest",
  "icons/icon-192.png", "icons/icon-512.png", "icons/apple-touch-icon.png"];

self.addEventListener("install", function (event) {
  event.waitUntil(caches.open(VERSION).then(function (c) { return c.addAll(SHELL); })
    .then(function () { return self.skipWaiting(); }));
});

self.addEventListener("activate", function (event) {
  event.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== VERSION; })
      .map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

function networkFirst(request) {
  return fetch(request).then(function (response) {
    if (response.ok) {
      var copy = response.clone();
      caches.open(VERSION).then(function (c) { c.put(request, copy); });
    }
    return response;
  }).catch(function () {
    return caches.match(request, { ignoreSearch: true }).then(function (hit) {
      return hit || Response.error();
    });
  });
}

function cacheFirst(request) {
  return caches.match(request).then(function (hit) {
    return hit || fetch(request).then(function (response) {
      if (response.ok || response.type === "opaque") {
        var copy = response.clone();
        caches.open(VERSION).then(function (c) { c.put(request, copy); });
      }
      return response;
    });
  });
}

self.addEventListener("fetch", function (event) {
  var req = event.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin === location.origin) {
    if (/\/data\/data\.json$/.test(url.pathname)) return event.respondWith(networkFirst(req));
    if (/\/(data\/icons|art|icons)\//.test(url.pathname)) return event.respondWith(cacheFirst(req));
    return event.respondWith(networkFirst(req));   // shell: fresh when online
  }
  if (/fonts\.(googleapis|gstatic)\.com$/.test(url.hostname)) event.respondWith(cacheFirst(req));
});
