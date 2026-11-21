/* Apply the theme before first paint (loaded in <head>). HEIST has one look: bold lavender. */
document.documentElement.dataset.theme = 'lavender';
document.documentElement.classList.add('heist');
try { var hs = (JSON.parse(localStorage.getItem('yoko.student.v1') || '{}').settings || {});
  var dk = typeof hs.dark === 'boolean' ? hs.dark : matchMedia('(prefers-color-scheme: dark)').matches;
  if (dk) document.documentElement.classList.add('dark'); } catch (e) { /* first visit */ }
try { if (localStorage.getItem('heist.sideCollapsed') === '1') document.documentElement.classList.add('side-collapsed'); } catch (e) { /* storage blocked */ }
