import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { mkdtemp, mkdir, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

test('offline bundle is complete, scoped, and preserves other applications caches', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'heist-offline-'));
  await mkdir(join(directory, 'canvaskit'));
  for (const file of ['index.html', 'main.dart.js', 'sqlite3.wasm', 'sqflite_sw.js', 'canvaskit/canvaskit.wasm']) {
    await writeFile(join(directory, file), file);
  }
  execFileSync(process.execPath, ['tool/build_offline.mjs', directory]);
  const source = await readFile(join(directory, 'offline-sw.js'), 'utf8');
  const handlers = {};
  const deleted = [];
  let assets, requested, claimed = false, skipped = false;
  const cache = {
    addAll: async list => { assets = list; },
    match: async request => { requested = request; return { offline: true }; },
  };
  vm.runInNewContext(source, {
    URL, fetch: () => { throw Error('Offline: fetch must not run for cached navigation'); },
    self: {
      registration: { scope: 'https://example.com/heist/' },
      addEventListener: (name, callback) => { handlers[name] = callback; },
      skipWaiting: async () => { skipped = true; },
      clients: { claim: async () => { claimed = true; } },
    },
    caches: {
      open: async () => cache,
      keys: async () => ['unrelated-app', 'heist-flutter-/another/-old', 'heist-flutter-/heist/-old'],
      delete: async key => { deleted.push(key); },
    },
  });
  let pending;
  handlers.install({ waitUntil: p => { pending = p; } });
  await pending;
  assert.equal(assets.length, 5);
  assert.ok(assets.includes('./sqlite3.wasm'));
  assert.ok(assets.includes('./canvaskit/canvaskit.wasm'));
  assert.ok(skipped);
  handlers.activate({ waitUntil: p => { pending = p; } });
  await pending;
  assert.deepEqual(deleted, ['heist-flutter-/heist/-old']);
  assert.ok(claimed);
  handlers.fetch({ request: { method: 'GET', url: 'https://example.com/heist/', mode: 'navigate' }, respondWith: p => { pending = p; } });
  assert.deepEqual(await pending, { offline: true });
  assert.equal(requested, 'https://example.com/heist/index.html');
  let intercepted = false;
  handlers.fetch({ request: { method: 'GET', url: 'https://api.example.com/', mode: 'cors' }, respondWith: () => { intercepted = true; } });
  assert.equal(intercepted, false);
});

test('missing SQLite web assets blocks the offline build', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'heist-missing-'));
  await writeFile(join(directory, 'index.html'), 'fixture');
  assert.throws(() => execFileSync(process.execPath, ['tool/build_offline.mjs', directory], { stdio: 'pipe' }), /Missing offline asset/);
});
