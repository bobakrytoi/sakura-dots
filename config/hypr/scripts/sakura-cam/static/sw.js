// sakura mono - sakura-cam: keeps the page itself on the phone, so the home-screen app opens even when the
// address it was added from is not reachable (e.g. Wi-Fi off, USB tethering on) and then finds the PC by IP.
const V = "sakura-cam-v1";
const SHELL = ["/", "/app.js", "/style.css", "/manifest.webmanifest", "/font/inter.ttf", "/icon-192.png", "/apple-touch-icon.png", "/keepawake.mp4"];
self.addEventListener("install", e => { e.waitUntil(caches.open(V).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.pathname === "/ws" || u.pathname === "/ping") return;
  // network first (fresh page when the PC is there), the cache when it is not
  e.respondWith(fetch(e.request).then(r => { const c = r.clone(); caches.open(V).then(x => x.put(e.request, c)); return r; })
    .catch(() => caches.match(e.request, { ignoreSearch: true })));
});
