/* HEIST service worker: makes the installed app open offline.
   The page and its own code (js/, css/) are fetched fresh when online (so updates arrive together) and fall back to the cached copy offline.
   Everything else is cache-first; the large OCR files are cached the first time they're used. */
const CACHE = 'heist-main-v77';   // bump the number every session
const PREFIX = 'heist-main-';    // only ever delete our own caches (main HEIST may share this origin)
const CORE = [
  './', './index.html', './manifest.webmanifest', './prices.json',
  './assets/chart.umd.min.js', './assets/logo.png', './assets/favicon.png', './assets/heist-logo.png', './assets/apple-touch-icon.png', './assets/icon-192.png', './assets/icon-512.png',
  './assets/fonts/instrument-serif-latin-400-normal.woff2', './assets/fonts/instrument-serif-latin-400-italic.woff2', './assets/fonts/rubik-latin-800-normal.woff2', './assets/fonts/rubik-latin-800-italic.woff2', './assets/fonts/rubik-latin-ext-800-normal.woff2', './assets/fonts/inter-400.woff2', './assets/fonts/inter-500.woff2', './assets/fonts/inter-600.woff2', './assets/fonts/inter-700.woff2', './assets/fonts/dm-sans-latin-400-normal.woff2', './assets/fonts/dm-sans-latin-500-normal.woff2', './assets/fonts/dm-sans-latin-600-normal.woff2', './assets/fonts/dm-sans-latin-700-normal.woff2', './assets/fonts/dm-sans-latin-ext-400-normal.woff2', './assets/fonts/dm-sans-latin-ext-500-normal.woff2', './assets/fonts/dm-sans-latin-ext-600-normal.woff2', './assets/fonts/dm-sans-latin-ext-700-normal.woff2', './assets/fonts/space-grotesk-latin-500-normal.woff2', './assets/fonts/space-grotesk-latin-600-normal.woff2', './assets/fonts/space-grotesk-latin-700-normal.woff2', './assets/fonts/space-grotesk-latin-ext-500-normal.woff2', './assets/fonts/space-grotesk-latin-ext-600-normal.woff2', './assets/fonts/space-grotesk-latin-ext-700-normal.woff2', './assets/fonts/anton-latin-400-normal.woff2', './assets/fonts/anton-latin-ext-400-normal.woff2',
  './assets/pdfjs/pdf.min.js', './assets/pdfjs/pdf.worker.min.js',
  './assets/sc-add.png', './assets/sc-receipt.png', './assets/sc-message.png', './assets/sc-calendar.png',
  // app code: keep in sync with the <script> tags in index.html
  './css/app.css',
  './css/heist.css',
  './js/theme-boot.js',
  './js/finmath.js',
  './js/selftests.js',   // loaded on demand, cached for offline
  './js/utils.js',
  './js/i18n.js',
  './js/state.js',
  './js/charts.js',
  './js/ui-shared.js', './js/modes.js',
  './js/page-dashboard.js',
  './js/page-debt.js',
  './js/page-budget.js',
  './js/suggestions.js',
  './js/page-goals.js',
  './js/fun.js',
  './js/tour.js',
  './js/page-wallet.js',
  './js/payslip.js',
  './js/more.js',
  './js/import.js',
  './js/rewards.js',
  './js/pet.js',
  './js/challenges.js',
  './js/commands.js',
  './js/ai.js',
  './js/commandbar.js', './js/planner.js',
  './js/qrcode.js',
  './js/bill-split.js',
  './js/wrapped.js',
  './js/insights.js',
  './js/global.js',
  './js/receipt.js',
  './js/calendar.js',
  './js/sub-checkin.js',
  './js/motion.js',
  './js/page-travel.js', './js/router.js',
  './js/modals.js',
  './js/sync.js',
  './js/groups.js', './js/heists.js',
  './js/export.js',
  './js/actions.js',
  './js/init.js'
];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).then(() => self.skipWaiting()));
});
// activate also clears heist-vNN, this app's caches from before they got their own name
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => (k.startsWith(PREFIX) && k !== CACHE) || /^heist-v\d+$/.test(k)).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
const SHARED = 'heist-shared';   // screenshots and text shared into HEIST from another app (Android share sheet)
async function takeShare(req) {
  const fd = await req.formData();
  const cache = await caches.open(SHARED);
  for (const k of await cache.keys()) await cache.delete(k);
  const files = fd.getAll('shots').filter(f => f && typeof f === 'object' && f.size > 0).slice(0, 10);
  await Promise.all(files.map((f, i) => cache.put(`./shared/file-${i}`, new Response(f, { headers: { 'content-type': f.type || 'image/png', 'x-name': encodeURIComponent(f.name || 'screenshot-' + i + '.png') } }))));
  const text = ['title', 'text', 'url'].map(k => fd.get(k)).filter(v => typeof v === 'string' && v.trim()).join('\n');
  if (text) await cache.put('./shared/text', new Response(text, { headers: { 'content-type': 'text/plain' } }));
  return Response.redirect('./index.html#do/shared', 303);
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method === 'POST' && new URL(req.url).pathname.endsWith('/share-target')) {
    e.respondWith(takeShare(req).catch(() => Response.redirect('./index.html#do/import-sms', 303)));
    return;
  }
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  if (req.mode === 'navigate') {
    if (!/\/(index\.html)?$/.test(new URL(req.url).pathname)) {   // other pages (privacy, terms, 404): never stored as the app itself
      e.respondWith(fetch(req).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); } return res; })
        .catch(() => caches.match(req).then(hit => hit || caches.match('./index.html'))));
      return;
    }
    e.respondWith(fetch(req, { cache: 'no-cache' }).then(res => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put('./index.html', copy)); }
      return res;
    }).catch(() => caches.match('./index.html')));
    return;
  }
  if (/\/(js|css)\/[^/]+\.(js|css)$/.test(new URL(req.url).pathname)) {   // app code: newest when online, saved copy offline
    e.respondWith(fetch(req, { cache: 'no-cache' }).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); } return res; }).catch(() => caches.match(req)));
    return;
  }
  if (/\/prices\.json$/.test(new URL(req.url).pathname)) {   // price list: newest when online, saved copy offline
    e.respondWith(fetch(req).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put('./prices.json', copy)); } return res; }).catch(() => caches.match('./prices.json')));
    return;
  }
  e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
    return res;
  })));
});
