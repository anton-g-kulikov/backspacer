// Pick the cached theme before first paint; the host-stored value is applied in init().
(() => { let t = 'glass'; try { t = localStorage.getItem('theme') || t; } catch {}
  if (t !== 'terminal') t = 'glass';
  document.getElementById('css-terminal').disabled = t !== 'terminal';
  document.getElementById('css-glass').disabled = t !== 'glass';
  document.documentElement.dataset.theme = t; })();
