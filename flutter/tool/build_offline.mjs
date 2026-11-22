import { readdir, readFile, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';

const directory = process.argv[2] || 'build/web';
async function walk(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const nested = await Promise.all(entries.map(e => e.isDirectory() ? walk(join(root, e.name)) : [join(root, e.name)]));
  return nested.flat();
}
const files = (await walk(directory)).filter(f => !f.endsWith('offline-sw.js') && !f.endsWith('.map') && !f.endsWith('flutter_service_worker.js')).sort();
const urls = files.map(f => './' + relative(directory, f).replaceAll('\\', '/'));
for (const required of ['./index.html', './main.dart.js', './sqlite3.wasm', './sqflite_sw.js']) {
  if (!urls.includes(required)) throw Error(`Missing offline asset ${required}. Run SQLite web setup and Flutter build first.`);
}
const hash = createHash('sha256');
for (const file of files) hash.update(await readFile(file));
const version = hash.digest('hex').slice(0, 16);
const source = `// Generated from every bundled asset; no CDN is needed for offline launch.
const CACHE_PREFIX = 'heist-flutter-' + new URL(self.registration.scope).pathname + '-';
const CACHE = CACHE_PREFIX + ${JSON.stringify(version)};
const ASSETS = ${JSON.stringify(urls)};
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith(CACHE_PREFIX) && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (!url.href.startsWith(self.registration.scope)) return;
  event.respondWith(caches.open(CACHE).then(async cache => {
    const isAppPage = url.pathname === new URL(self.registration.scope).pathname || url.pathname === new URL('index.html', self.registration.scope).pathname;
    const asset = event.request.mode === 'navigate' && isAppPage ? new URL('index.html', self.registration.scope).href : event.request;
    const cached = await cache.match(asset);
    if (cached) return cached;
    return fetch(event.request);
  }));
});
`;
await writeFile(join(directory, 'offline-sw.js'), source);
console.log(`Bundled ${urls.length} offline assets, version ${version}.`);
