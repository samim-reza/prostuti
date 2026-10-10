// Applies the stored theme ("light" | "dark" | "system") before React mounts,
// so the page never flashes the wrong colours.
(function () {
  var pref = 'system';
  try {
    pref = localStorage.getItem('prostuti-admin-theme') || 'system';
  } catch (e) {
    /* storage unavailable: follow the system */
  }
  var dark = pref === 'dark' || (pref === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.classList.toggle('dark', dark);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
})();
