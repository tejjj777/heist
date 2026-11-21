/* Apply the theme before first paint (loaded in <head>). HEIST has one palette: lavender and white.
   data-look picks the style while we choose one: soft, bold or mix (?look=bold in the address works too). */
(function () {
  var de = document.documentElement, look = 'soft';
  de.dataset.theme = 'lavender';
  de.classList.add('heist');
  try {
    var q = (location.search.match(/[?&]look=(soft|bold|mix)/) || [])[1];
    if (q) localStorage.setItem('heist.look', q);
    look = q || localStorage.getItem('heist.look') || look;
  } catch (e) { /* storage blocked */ }
  de.dataset.look = look;
})();
