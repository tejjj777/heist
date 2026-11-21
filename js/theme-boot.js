/* One-time move of saved data from the app's old name (before it was HEIST), so nobody loses anything.
   This is the only place the old names appear. It copies, never deletes: the other HEIST apps on this site may need them too. */
window.heistMoving = (function () {
  var KEYS = {
    'heist.v1': 'yoko.student.v1',
    'heist.prices': 'yoko.student.prices',
    'heist.account': 'yoko.student.account',
    'heist.sync-clash': 'yoko.student.sync-clash',
    'heist.groups.outbox': 'yoko.groups.outbox'
  };
  try {
    Object.keys(KEYS).forEach(function (k) {
      if (localStorage.getItem(k) !== null) return;
      var v = localStorage.getItem(KEYS[k]);
      if (v === null) return;
      if (/\.v1$/.test(k)) try {
        var s = JSON.parse(v), st = s.settings || {};
        if (/^yoko!?$/i.test(st.petName || '')) st.petName = 'Slime';
        if (st.chartColors && st.chartColors !== 'rainbow') st.chartColors = 'heist';
        if (st.theme === 'yoko') st.theme = 'lavender';
        v = JSON.stringify(s);
      } catch (e) { /* keep as is */ }
      localStorage.setItem(k, v);
    });
  } catch (e) { /* storage blocked */ }
  var DBS = [['yoko-photos', 'photos', 'heist-photos'],
    ['yoko-student', 'kv', 'heist-backups']];
  var flag = 'heist.moved.heist';
  try { if (!DBS.length || localStorage.getItem(flag)) return Promise.resolve(); } catch (e) { return Promise.resolve(); }
  function copy(from, store, to) {
    return new Promise(function (done) {
      if (!window.indexedDB) return done();
      var made = false, items = [], r;
      try { r = indexedDB.open(from, 1); } catch (e) { return done(); }
      r.onupgradeneeded = function () { made = true; r.result.createObjectStore(store); };
      r.onerror = function () { done(); };
      r.onsuccess = function () {
        var old = r.result;
        if (made || !old.objectStoreNames.contains(store)) { old.close(); if (made) indexedDB.deleteDatabase(from); return done(); }
        var c = old.transaction(store).objectStore(store).openCursor();
        c.onsuccess = function () { var cur = c.result; if (cur) { items.push([cur.key, cur.value]); cur.continue(); } else { old.close(); write(); } };
        c.onerror = function () { old.close(); done(); };
      };
      function write() {
        if (!items.length) return done();
        var w = indexedDB.open(to, 1);
        w.onupgradeneeded = function () { w.result.createObjectStore(store); };
        w.onerror = function () { done(); };
        w.onsuccess = function () {
          var db = w.result, tx = db.transaction(store, 'readwrite'), os = tx.objectStore(store);
          items.forEach(function (it) { var g = os.get(it[0]); g.onsuccess = function () { if (g.result === undefined) os.put(it[1], it[0]); }; });
          tx.oncomplete = tx.onerror = tx.onabort = function () { db.close(); done(); };
        };
      }
    });
  }
  return Promise.all(DBS.map(function (d) { return copy(d[0], d[1], d[2]); }))
    .then(function () { try { localStorage.setItem(flag, '1'); } catch (e) { /* storage blocked */ } }, function () {});
})();

/* Apply the theme before first paint (loaded in <head>). HEIST has one look: bold lavender. */
document.documentElement.dataset.theme = 'lavender';
document.documentElement.classList.add('heist');
try { var hs = (JSON.parse(localStorage.getItem('heist.v1') || '{}').settings || {});
  var dk = typeof hs.dark === 'boolean' ? hs.dark : matchMedia('(prefers-color-scheme: dark)').matches;
  if (dk) document.documentElement.classList.add('dark');
  if (hs.simple === true) document.documentElement.classList.add('simple'); } catch (e) { /* first visit */ }
try { if (localStorage.getItem('heist.sideCollapsed') === '1') document.documentElement.classList.add('side-collapsed'); } catch (e) { /* storage blocked */ }
