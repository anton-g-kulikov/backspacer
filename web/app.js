/* ═══════════════════════════════════════════════════════════════════
   Bridge — talks to the Swift host. Falls back to a mock in a browser.
   Protocol:  JS  → bridge.call(op, args)  → Swift
              Swift → window.__backspacerReply(id, ok, payload)
   Ops: catalog, disk, fdaStatus, size{id}, info{id}, delete{id}, reveal{id}, openFDA
   Safety: JS only ever sends catalog *ids*. Paths are resolved by Swift
   from its own copy of catalog.json, so the web layer can't name a path.
   ═══════════════════════════════════════════════════════════════════ */
const native = window.webkit?.messageHandlers?.backspacer;
const pending = new Map(); let seq = 0;
window.__backspacerReply = (id, ok, payload) => {
  const p = pending.get(id); if (!p) return; pending.delete(id);
  ok ? p.res(payload) : p.rej(new Error(payload?.error || String(payload)));
};
const bridge = native
  ? { call: (op, args = {}) => new Promise((res, rej) => { const id = ++seq; pending.set(id, { res, rej }); native.postMessage({ id, op, args }); }) }
  : mockBridge();

function mockBridge() {
  const sizes = new Map(); let catalog; const roots = ['~/Projects'];
  const rnd = (a, b) => Math.round(a + Math.random() * (b - a));
  return {
    async call(op, args = {}) {
      await new Promise(r => setTimeout(r, op === 'size' ? rnd(80, 400) : 60));
      switch (op) {
        case 'catalog': {   // the Mac host filters to macOS entries (ADR-22); the mock does the same
          if (!catalog) { catalog = await (await fetch('../catalog.json')).json(); catalog.entries = catalog.entries.filter(e => !e.platforms || e.platforms.includes('macos')); }
          return catalog;
        }
        case 'disk': { const size = 245e9, freed = [...sizes.values()].reduce((a, b) => a + (b.freed || 0), 0); return { size, used: 193e9 - freed, free: 52e9 + freed }; }
        case 'fdaStatus': return { granted: false };
        case 'size': {
          const e = catalog.entries.find(x => x.id === args.id);
          if (e.fda) return { bytes: null, paths: [], fda: true };   // the mock reports FDA as not granted
          let s = sizes.get(args.id);
          if (!s) {
            s = { bytes: e.bucket === 'locked' ? rnd(4e8, 2e9) : (Math.random() < .2 ? 0 : rnd(1e7, 9e9)) };
            if (e.itemsCmd) {                           // command items: fake simulators / runtimes
              const names = e.id === 'xcode-runtimes' ? ['iOS 26.5 (23F77)', 'iOS 18.0 (22A3351)'] : ['iPhone 17 Pro · iOS 26.5', 'iPad Air 11-inch (M4) · iOS 26.5', 'iPhone SE · iOS 18.0'];
              s.items = names.map((label, i) => ({ key: `${e.id}-${i + 1}`, label, bytes: 0 }));
              let left = s.bytes; s.items.forEach((it, i) => { it.bytes = i === s.items.length - 1 ? left : Math.round(left * .5); left -= it.bytes; });
            } else if (e.glob || e.paths || e.children) {   // granular: invent 2–6 items that add up
              const n = rnd(2, 6), base = e.glob ? `${e.glob.root === '$PROJECTS' ? roots[0] || '~/Projects' : e.glob.root}/proj-` : e.paths ? '' : `${e.path}/`;
              s.items = Array.from({ length: n }, (_, i) => ({ path: e.paths ? e.paths[i % e.paths.length] + (i >= e.paths.length ? '-' + i : '') : `${base}${i + 1}/${e.glob ? (e.glob.name || (e.glob.names || [])[i % ((e.glob.names || []).length || 1)] || (e.glob.pathPatterns ? e.glob.pathPatterns[0].replace(/^\*\//, '') : 'build')) : 'item-' + (i + 1)}`, bytes: 0 }));
              let left = s.bytes; s.items.forEach((it, i) => { it.bytes = i === n - 1 ? left : Math.round(left * Math.random() * .6); left -= it.bytes; });
            }
            sizes.set(args.id, s);
          }
          return { bytes: s.bytes, paths: e.path ? [e.path] : e.paths || [], ...(s.items ? { items: s.items } : {}) };
        }
        case 'info': return { text: `(mock) output of infoCmd for ${args.id}\nline 2\nline 3` };
        case 'delete': {
          const s = sizes.get(args.id) || { bytes: 0 };
          const e = catalog.entries.find(x => x.id === args.id), tr = e.bucket === 'decide' && !e.sudo && !e.deleteCmd && !e.itemsCmd;
          if (args.item) {
            const it = s.items?.find(x => (x.key ?? x.path) === args.item); if (!it) throw new Error('Not one of the items: ' + args.item);
            s.items = s.items.filter(x => x !== it); s.bytes -= it.bytes; s.freed = (s.freed || 0) + it.bytes; return { ok: true, freedBytes: it.bytes, ...(tr && !it.key ? { trashed: true } : {}) };
          }
          const freed = s.bytes; sizes.set(args.id, { bytes: 0, freed: (s.freed || 0) + freed }); return { ok: true, freedBytes: freed, ...(tr ? { trashed: true } : {}) };
        }
        case 'reveal': case 'openFDA': return { ok: true };
        case 'appInfo': return { version: 'dev', build: 'browser' };
        case 'log': return { ok: true };
        case 'scanHints': return { durations: {} };
        case 'logPath': case 'revealLog': return { path: '~/Library/Logs/Backspacer/Backspacer.log' };
        case 'checkUpdate': return { skipped: 'unconfigured' };
        case 'projectRoots': return { roots: roots.map(r => ({ path: r, display: r })) };
        case 'projects': { const r = roots[0] || '~/Projects', now = Math.floor(Date.now() / 1000); return { projects: [1, 2, 3, 4, 5, 6].map(i => ({ path: `${r}/proj-${i}`, display: `${r}/proj-${i}`, touched: i === 6 ? null : now - [3, 40, 200, 500, 900, 0][i - 1] * 86400, source: i % 2 ? 'git' : 'mtime' })) }; }
        case 'revealProject': return { ok: true };
        case 'addProjectRoot': { const r = window.prompt('Folder (mock):', '~/Developer'); if (r && !roots.includes(r)) roots.push(r); return { roots: roots.map(r => ({ path: r, display: r })) }; }
        case 'removeProjectRoot': { const i = roots.indexOf(args.path); if (i < 0) throw new Error('Not a project folder'); roots.splice(i, 1); return { roots: roots.map(r => ({ path: r, display: r })) }; }
        case 'prefGet': return { value: localStorage.getItem('pref.' + args.key) };
        case 'prefSet': localStorage.setItem('pref.' + args.key, args.value); return { ok: true };
        default: throw new Error('unknown op ' + op);
      }
    }
  };
}

/* ═══════════════════════════════════════════════════════════════════ */
const $ = s => document.querySelector(s);
const state = { catalog: null, size: new Map(), items: new Map(), selected: new Set(), showSmall: new Set(), projects: [], projectView: 'tool', projectSort: 'age', deleting: false, scanning: false, scanned: false, thr: 0, disk: null, roots: [] };
// fmt, esc, deletable, granular, hasInfo, explainHTML, sortProjects, deletingLabel, itemDeletable, itemId, trashes, itemName, isVisible,
// buildNesting, ownSize, hasSelectedParent, meterSegments, ORDER, THR come from logic.js.
const TRASH_NOTE = ' Put it back from Finder if you change your mind; empty the Trash to actually free the space.';
const afterTrash = () => { const t = state.catalog.entries.find(e => e.id === 'cache-trash'); if (t) scan([t]); };
// Rows measured below the current stop are hidden, deselected and left out of totals.
const minBytes = () => THR[state.thr];
// A row shows when it clears the size threshold — and, in the by-project view, when it is not a
// project build-output entry: those move into the Projects card (rows, select-all, bucket badges).
const isProjectEntry = id => entry(id)?.glob?.root === '$PROJECTS';
const visible = id => isVisible(state.size.get(id), minBytes()) && !(state.projectView === 'project' && isProjectEntry(id));

// Totals use each entry's *own* size (measured minus nested children) so nothing counts twice.
let NEST = { children: new Map(), parent: new Map() };
const own = id => ownSize(id, state.size, NEST);
const selectedParent = id => hasSelectedParent(id, state.selected, NEST);
/** Screen-reader announcements for things that otherwise only change visually. */
function announce(text) { const l = $('#live'); l.textContent = ''; setTimeout(() => { l.textContent = text; }, 50); }
/* A delete of gigabytes takes tens of seconds and the host says nothing until it returns, so the
   row says it for itself: the size cell reads "deleting…" and blinks (the word matters — reduced
   motion drops the blink), and the row is aria-busy. Nothing is disabled: state.deleting stops a
   second pass, and disabling the control that has focus would drop a screen reader to the body —
   the reason Scan uses aria-busy too (A4). */
function setBusy(el, sizeEl, on) {
  if (el) on ? el.setAttribute('aria-busy', 'true') : el.removeAttribute('aria-busy');
  if (!sizeEl) return;
  if (on) {
    sizeEl.dataset.was = sizeEl.textContent; sizeEl.dataset.wasCls = sizeEl.className;
    sizeEl.textContent = 'deleting…'; sizeEl.className = 'size pending';
  } else if (sizeEl.dataset.was !== undefined) {   // a failed delete leaves the row as it was
    sizeEl.textContent = sizeEl.dataset.was; sizeEl.className = sizeEl.dataset.wasCls;
    delete sizeEl.dataset.was; delete sizeEl.dataset.wasCls;
  }
}
/* The host reports what it has freed while a delete is still running (R28b). The row counts down
   from the size the page measured; a push for a row that is not working is ignored. */
window.__backspacerProgress = (id, freedBytes) => {
  const el = document.querySelector(`.row[data-id="${id}"] [data-size]`);
  if (!el || el.dataset.was === undefined) return;
  el.textContent = fmt(Math.max(0, (state.size.get(id) || 0) - freedBytes));
};
const log = (msg, cls = '') => {
  const p = $('#log'); p.insertAdjacentHTML('beforeend', `<span class="${cls}">${new Date().toTimeString().slice(0, 8)}  ${esc(msg)}</span>\n`); p.scrollTop = p.scrollHeight;
  bridge.call('log', { level: cls === 'err' ? 'error' : 'info', message: msg }).catch(() => {});   // also to the diagnostics file
};
window.addEventListener('error', e => bridge.call('log', { level: 'error', message: `${e.message} (${e.filename}:${e.lineno})` }).catch(() => {}));
window.addEventListener('unhandledrejection', e => bridge.call('log', { level: 'error', message: 'unhandled: ' + (e.reason?.message || e.reason) }).catch(() => {}));

/* ── theme ──────────────────────────── */
// Two <style> sheets, one enabled at a time. Chosen from the app's View menu
// (window.__setTheme) or ?theme= in a browser; stored by the host (UserDefaults)
// and cached in localStorage so the first paint is already right.
const THEMES = ['glass', 'terminal'];
function applyTheme(t) {
  if (!THEMES.includes(t)) t = 'glass';
  for (const x of THEMES) document.getElementById('css-' + x).disabled = x !== t;
  document.documentElement.dataset.theme = t;
  document.querySelectorAll('#theme button').forEach(b => { b.classList.toggle('on', b.dataset.theme === t); b.setAttribute('aria-pressed', String(b.dataset.theme === t)); });
  try { localStorage.setItem('theme', t); } catch {}
  requestAnimationFrame(() => { syncGutter(); syncBars(); });
}
window.__setTheme = t => { applyTheme(t); bridge.call('prefSet', { key: 'theme', value: t }).catch(() => {}); };
// Scrollbar track: main always shows it (overflow-y: scroll), so its width is a constant per theme.
// --sb is that width; main pads its left by it and the header/footer inset both sides by it, so
// all three share the same edges. Measured at load and on theme/resize — never as a side effect of
// the list changing.
function syncGutter() { const m = document.querySelector('main'); document.documentElement.style.setProperty('--sb', (m.offsetWidth - m.clientWidth) + 'px'); }
window.addEventListener('resize', syncGutter);
syncGutter();
// Glass overlays the list with the header and footer; the list pads itself by their heights so the
// first and last rows start in the clear. Observed, because the header stacks on narrow windows and
// the footer grows when the Log panel opens. Terminal keeps the bars in flow (padding stays 0).
function syncBars() {
  const h = document.querySelector('header'), f = document.querySelector('footer');
  const overlay = getComputedStyle(h).position === 'absolute';
  // 26 px of clear space below the header, the same as above the footer (10 + the last card's 16 margin).
  document.documentElement.style.setProperty('--header-h', overlay ? (h.offsetHeight + 26) + 'px' : '0px');
  document.documentElement.style.setProperty('--footer-h', overlay ? (f.offsetHeight + 10) + 'px' : '0px');
}
new ResizeObserver(syncBars).observe(document.querySelector('header'));
new ResizeObserver(syncBars).observe(document.querySelector('footer'));
syncBars();
$('#theme').onclick = e => { const t = e.target.dataset.theme; if (t) window.__setTheme(t); };

/* ── project folders ────────────────── */
const projectEntries = () => state.catalog.entries.filter(e => e.glob?.root === '$PROJECTS');
function renderRoots(roots) {
  state.roots = roots;
  const n = $('#rootsNotice'); n.hidden = false;
  $('#rootsText').innerHTML = roots.length
    ? '<b>Project folders.</b> Build output like node_modules and Pods is searched here.'
    : '<b>No project folders yet.</b> Build output like node_modules and Pods is only searched inside folders you add.';
  $('#rootsChips').innerHTML = roots.map(r => `<span class="chip">${esc(r.display)}<button data-removeroot="${esc(r.path)}" aria-label="Stop searching ${esc(r.display)}" title="Stop searching here">×</button></span>`).join('');
  // the grey path line under each project entry names the roots
  for (const e of projectEntries()) {
    const el = document.querySelector(`.row[data-id="${e.id}"] .path`);
    if (el) { const txt = `${roots.map(r => r.display).join(' · ') || 'project folders'}/**/${e.glob.name || (e.glob.names || e.glob.pathPatterns || []).join('|')}`; el.textContent = txt; el.title = txt; }
  }
}
async function changeRoots(op, args) {
  try {
    const before = state.roots.map(r => r.path).join('\n');
    const r = await bridge.call(op, args); renderRoots(r.roots);
    if (state.roots.map(r => r.path).join('\n') !== before) { log('project folders: ' + (state.roots.map(r => r.display).join(', ') || 'none')); scan(projectEntries()); }
  } catch (err) { log(err.message, 'err'); }
}
$('#rootsAdd').onclick = () => changeRoots('addProjectRoot');
$('#rootsChips').onclick = e => { const b = e.target.closest('[data-removeroot]'); if (b) changeRoots('removeProjectRoot', { path: b.dataset.removeroot }); };

async function init() {
  applyTheme(document.documentElement.dataset.theme);
  const q = new URLSearchParams(location.search).get('theme');
  if (q) window.__setTheme(q);
  else bridge.call('prefGet', { key: 'theme' }).then(r => { if (r.value) applyTheme(r.value); }).catch(() => {});
  bridge.call('prefGet', { key: 'minSize' }).then(r => { if (r.value != null) setThreshold(r.value, false); }).catch(() => {});
  bridge.call('prefGet', { key: 'projectView' }).then(r => setProjectView(r.value || 'tool', false)).catch(() => setProjectView('tool', false));
  bridge.call('prefGet', { key: 'projectSort' }).then(r => setProjectSort(r.value || 'age', false)).catch(() => setProjectSort('age', false));
  bridge.call('appInfo').then(r => { $('#aboutVersion').textContent = r.version; $('#aboutVersion').title = 'build ' + r.build; }).catch(() => {});
  bridge.call('logPath').then(r => { $('#logPath').textContent = r.path.replace(/^\/Users\/[^/]+/, '~'); }).catch(() => {});
  $('#revealLog').onclick = () => bridge.call('revealLog').catch(err => log(err.message, 'err'));
  // Updates are Sparkle's (ADR-21): the button asks it to check (it shows its own window); when
  // it has found and downloaded a version the app calls __updateFound and the page shows the notice.
  window.__checkUpdates = async () => {
    const out = $('#updResult');
    try {
      const r = await bridge.call('checkUpdate');
      out.textContent = r.skipped === 'unconfigured' ? 'Updates aren’t configured in this build.' : 'Checking…';
    } catch (e) { out.textContent = e.message; log('update check: ' + e.message, 'err'); }
  };
  window.__updateFound = version => {
    const text = `${version} is ready to install — Backspacer asks before relaunching.`;
    const notice = $('#updNotice'); notice.textContent = text; notice.hidden = false;
    $('#updResult').textContent = text;
    announce(text);
  };
  $('#checkUpd').onclick = () => { window.__checkUpdates(); };
  bridge.call('prefGet', { key: 'autoUpdateCheck' }).then(r => { $('#autoUpd').checked = r.value !== '0'; }).catch(() => {});
  $('#autoUpd').onchange = e => bridge.call('prefSet', { key: 'autoUpdateCheck', value: e.target.checked ? '1' : '0' }).catch(() => {});
  state.catalog = await bridge.call('catalog');
  NEST = buildNesting(state.catalog.entries);
  render();
  refreshDisk();
  bridge.call('fdaStatus').then(r => { $('#fdaNotice').hidden = !!r.granted; }).catch(() => {});
  bridge.call('projectRoots').then(r => renderRoots(r.roots)).catch(() => {});
  scan();
}

function render() {
  const root = $('#buckets'); root.innerHTML = '';
  for (const b of ORDER) {
    const entries = state.catalog.entries.filter(e => e.bucket === b);
    if (!entries.length) continue;
    const meta = state.catalog.buckets[b];
    const collapsed = ['keep', 'locked'].includes(b);
    const sec = document.createElement('section'); sec.className = 'bucket' + (collapsed ? ' collapsed' : ''); sec.dataset.bucket = b;
    sec.setAttribute('aria-labelledby', `bucket-h-${b}`);   // a named region: screen readers can jump bucket to bucket
    const anyDel = entries.some(deletable);
    sec.innerHTML = `
      <div class="bucket-head">
        <span class="dot" style="background:var(--${b})"></span>
        <div class="title"><h2><button type="button" id="bucket-h-${b}" aria-expanded="${!collapsed}" aria-controls="bucket-${b}" aria-describedby="bucket-blurb-${b}">${meta.title}</button></h2><small id="bucket-blurb-${b}">${meta.blurb}</small></div>
        <span class="total" data-total="${b}" style="--c:var(--${b})">—</span>
        ${anyDel ? `<label class="sel"><input type="checkbox" data-selall="${b}" aria-label="Select all in ${esc(meta.title)}">all</label>` : '<span></span>'}
      </div>
      <div class="bucket-body" id="bucket-${b}"></div>`;
    const body = sec.querySelector('.bucket-body');
    let group = null;
    for (const e of entries) {
      if (e.group !== group) { group = e.group; body.insertAdjacentHTML('beforeend', `<div class="group-lbl">${esc(group)}</div>`); }
      const canDel = deletable(e);
      const badges = [e.sudo ? '<span class="badge admin">admin</span>' : '', e.manual ? '<span class="badge manual">manual</span>' : '', e.fda ? '<span class="badge fda" title="Needs Full Disk Access to measure">disk access</span>' : ''].join('');
      const globRoot = e.glob && (e.glob.root === '$PROJECTS' ? (state.roots.map(r => r.display).join(' · ') || 'project folders') : e.glob.root);
      const pathTxt = e.path || (e.paths ? e.paths.join('  ·  ') : e.glob ? `${globRoot}/**/${e.glob.name || (e.glob.names || e.glob.pathPatterns || []).join('|')}` : '');
      body.insertAdjacentHTML('beforeend', `
        <div class="row" data-id="${e.id}">
          ${canDel ? `<input type="checkbox" data-sel="${e.id}" aria-label="${esc(e.label)}">` : '<span></span>'}
          <div class="name">
            <div class="label">${esc(e.label)}${badges}</div>
            ${e.note ? `<div class="note">${esc(e.note)}</div>` : ''}
            ${pathTxt ? `<div class="path" title="${esc(pathTxt)}">${esc(pathTxt)}</div>` : ''}
          </div>
          <span class="size pending" data-size="${e.id}">…</span>
          <div class="actions">
            ${hasInfo(e) ? `<button class="btn small" data-info="${e.id}" aria-expanded="false" aria-controls="info-${e.id}" aria-label="Details for ${esc(e.label)}">Details</button>` : '<span></span>'}
            ${(e.path || e.paths) ? `<button class="btn small" data-reveal="${e.id}" aria-label="Reveal ${esc(e.label)}">Reveal</button>` : '<span></span>'}
            ${canDel ? `<button class="btn small danger" data-del="${e.id}" aria-label="Delete ${esc(e.label)}">Delete</button>` : '<span></span>'}
          </div>
          <div class="info-out" data-infoout="${e.id}" id="info-${e.id}" hidden></div>
        </div>`);
    }
    root.appendChild(sec);
  }
}

async function refreshDisk() {
  try {
    const d = state.disk = await bridge.call('disk');
    $('#diskUsed').textContent = `${fmt(d.used)} used of ${fmt(d.size)}`;
    $('#diskFree').textContent = `${fmt(d.free)} free`;
    updateMeter();
  } catch (e) { log('disk: ' + e.message, 'err'); }
}

// Disk meter: one segment per bucket in its colour, then everything else that's
// used. Counts every measured entry, regardless of the size threshold.
function updateMeter() {
  const d = state.disk; if (!d || !state.catalog) return;
  const bar = $('#diskBar');
  const seg = (b, bytes, title) => {
    let el = bar.querySelector(`[data-seg="${b}"]`);
    if (!el) { el = document.createElement('i'); el.dataset.seg = b; el.style.setProperty('--c', `var(--${b})`); bar.appendChild(el); }
    el.style.width = (bytes / d.size * 100) + '%'; el.title = `${title} — ${fmt(bytes)}`;
  };
  const bytes = Object.fromEntries(ORDER.map(b => [b, state.catalog.entries.filter(e => e.bucket === b).reduce((a, e) => a + own(e.id), 0)]));
  const segs = meterSegments(d, bytes, state.catalog.buckets);
  for (const s of segs) seg(s.seg, s.bytes, s.title);
  bar.setAttribute('aria-label', `${fmt(d.used)} used of ${fmt(d.size)}, ${fmt(d.free)} free. ` + segs.filter(s => s.bytes).map(s => `${s.title} ${fmt(s.bytes)}`).join(', '));
  bar.classList.toggle('crit', d.used / d.size >= .95);
}

async function scan(only) {
  if (state.scanning) return; state.scanning = true;
  $('#scan').setAttribute('aria-busy', 'true'); updateScanBtn(); startScanWords(); announce('Scanning');
  const entries = only || state.catalog.entries;
  for (const e of entries) { state.size.delete(e.id); state.items.delete(e.id); const el = document.querySelector(`[data-size="${e.id}"]`); el.textContent = '…'; el.className = 'size pending'; }
  let hints = {}; try { hints = (await bridge.call('scanHints')).durations || {}; } catch {}
  const queue = scanOrder(entries, hints); const workers = Array.from({ length: SCAN_WORKERS }, worker);
  async function worker() {
    while (queue.length) {
      const e = queue.shift();
      try {
        const r = await bridge.call('size', { id: e.id });
        state.size.set(e.id, r.bytes); if (r.items) state.items.set(e.id, r.items);
        const el = document.querySelector(`[data-size="${e.id}"]`);
        el.textContent = rowSizeText(r.bytes, false, !!r.fda); el.className = 'size' + (r.bytes === 0 || r.bytes == null ? ' zero' : '');
        if (r.fda) el.title = 'Needs Full Disk Access — grant it in System Settings, then Rescan';
      } catch (err) { state.size.set(e.id, null); log(`${e.label}: ${err.message}`, 'err'); const el = document.querySelector(`[data-size="${e.id}"]`); el.textContent = '?'; el.className = 'size zero'; }
      updateTotals();
    }
  }
  await Promise.all(workers);
  state.scanning = false; state.scanned = true; $('#scan').setAttribute('aria-busy', 'false'); updateScanBtn();
  announce('Scan complete');
  await refreshProjects();
  stopScanWords();   // no "reclaimable" total — how much to reclaim is the user's call
  log('scan complete');
}

const bucketTotal = b => state.catalog.entries.filter(e => e.bucket === b && visible(e.id)).reduce((a, e) => a + own(e.id), 0);
function updateTotals() {
  applyThreshold(); updateMeter();
  for (const b of ORDER) { const el = document.querySelector(`[data-total="${b}"]`); if (el) el.textContent = fmt(bucketTotal(b)); }
  // The tagline counts the same bytes in both views: the buckets, plus what the Projects card took over.
  const projectBytes = state.projectView === 'project' ? projectEntries().filter(e => RECLAIMABLE.includes(e.bucket) && isVisible(state.size.get(e.id), minBytes())).reduce((a, e) => a + own(e.id), 0) : 0;
  $('.tagline').textContent = taglineText(RECLAIMABLE.reduce((a, b) => a + bucketTotal(b), 0) + projectBytes);
  const n = state.selected.size, bytes = [...state.selected].reduce((a, id) => a + (selectedParent(id) ? 0 : state.size.get(id) || 0), 0);
  $('#sum').innerHTML = n ? `<b>${n}</b> selected · <b>${fmt(bytes)}</b>` : 'Nothing selected';
  if (!state.deleting) $('#deleteSel').disabled = !n;   // mid-delete the button carries the busy label; the loop settles it at the end
}

function applyThreshold() {
  state.showSmall.clear();
  renderProjects();
  for (const id of state.items.keys()) { const out = document.querySelector(`[data-infoout="${id}"]`); if (out && !out.hidden) renderItems(id); }
  for (const id of [...state.selected]) if (!visible(id)) { state.selected.delete(id); const cb = document.querySelector(`[data-sel="${id}"]`); if (cb) cb.checked = false; }
  for (const sec of document.querySelectorAll('section.bucket')) {
    let any = false, lbl = null, lblAny = false;
    const flushLbl = () => { if (lbl) lbl.hidden = !lblAny; };
    for (const el of sec.querySelector('.bucket-body').children) {
      if (el.classList.contains('group-lbl')) { flushLbl(); lbl = el; lblAny = false; continue; }
      if (!el.classList.contains('row')) continue;
      const v = visible(el.dataset.id); el.hidden = !v; if (v) { any = true; lblAny = true; }
    }
    flushLbl();
    let empty = sec.querySelector('.empty');
    if (!any && !empty) { empty = document.createElement('div'); empty.className = 'empty'; sec.querySelector('.bucket-body').appendChild(empty); }
    if (empty) { empty.hidden = any; empty.textContent = `Nothing ${fmt(minBytes())} or larger.`; }
  }
}

function setThreshold(i, save) {
  state.thr = Math.max(0, Math.min(THR.length - 1, i | 0));
  $('#thr').value = state.thr; $('#thrLbl').textContent = fmt(minBytes()); $('#thr').setAttribute('aria-valuetext', fmt(minBytes()));
  if (state.catalog) updateTotals();
  if (save) bridge.call('prefSet', { key: 'minSize', value: String(state.thr) }).catch(() => {});
}

/* ── events ─────────────────────────── */
let scanTimer = null, scanTick = 0;
function startScanWords() {
  clearInterval(scanTimer); scanTick = 0;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) { $('#scan').textContent = 'Scanning…'; return; }
  const words = shuffled(SCAN_WORDS);   // a different order every scan
  $('#scan').textContent = scanFrame(0, words);
  scanTimer = setInterval(() => { $('#scan').textContent = scanFrame(++scanTick, words); }, 250);
}
function stopScanWords() { clearInterval(scanTimer); scanTimer = null; updateScanBtn(); }
// While scanning the button carries the verbs (startScanWords); at rest it says what a click does.
function updateScanBtn() { $('#scan').textContent = state.scanning ? 'Scanning…' : state.scanned ? 'Rescan' : 'Scan'; }
$('#scan').onclick = () => scan();
$('#thr').oninput = e => setThreshold(e.target.value, true);
// The by-project view (A19): build output folded into the project it belongs to, stalest first.
// The bridge lists the projects (and when each was last touched); the page only regroups items
// it already has from the $PROJECTS entries. Deleting a project's output is the per-item delete,
// one validated call per item, after one confirmation listing them all.
async function refreshProjects() {
  try { state.projects = (await bridge.call('projects')).projects || []; } catch { state.projects = []; }
  renderProjects();
}
function setProjectView(v, save) {
  state.projectView = v === 'project' ? 'project' : 'tool';
  document.querySelectorAll('#projView button').forEach(b => { const on = b.dataset.view === state.projectView; b.classList.toggle('on', on); b.setAttribute('aria-pressed', String(on)); });
  if (state.catalog) updateTotals();   // applyThreshold hides or restores the project rows and renders the card
  if (save) bridge.call('prefSet', { key: 'projectView', value: state.projectView }).catch(() => {});
}
$('#projView').onclick = e => { const v = e.target.dataset.view; if (v) setProjectView(v, true); };
function setProjectSort(v, save) {
  state.projectSort = v === 'size' ? 'size' : 'age';
  document.querySelectorAll('#projSort button').forEach(b => { const on = b.dataset.sort === state.projectSort; b.classList.toggle('on', on); b.setAttribute('aria-pressed', String(on)); });
  if (state.catalog) renderProjects();
  if (save) bridge.call('prefSet', { key: 'projectSort', value: state.projectSort }).catch(() => {});
}
$('#projSort').onclick = e => { const v = e.target.dataset.sort; if (v) setProjectSort(v, true); };
function renderProjects() {
  const sec = $('#projects'), body = $('#projects-body');
  const on = state.projectView === 'project' && state.scanned;
  sec.hidden = !on; if (!on) return;
  const groups = sortProjects(groupByProject(state.projects, projectEntries(), state.items).filter(g => g.bytes >= minBytes() || g.path === ''), state.projectSort);
  const now = Math.floor(Date.now() / 1000);
  $('#projectsTotal').textContent = fmt(groups.reduce((a, g) => a + g.bytes, 0));
  if (!groups.length) { body.innerHTML = `<div class="empty">No build output ${fmt(minBytes())} or larger in your project folders${state.roots.length ? '' : ' — add a folder above'}.</div>`; return; }
  body.innerHTML = groups.map((p, i) => {
    const stale = p.touched != null && now - p.touched > 180 * 86400;
    const what = p.items.map(it => `${esc(it.name)} ${fmt(it.bytes)}`).join(' · ');
    const canDel = p.items.some(it => itemDeletable(entry(it.entryId)));
    return `
    <div class="prow" data-project="${esc(p.path)}">
      <span></span>
      <div>
        <div class="name">${esc(p.display)}</div>
        <div class="what" title="${what}">${what}</div>
      </div>
      <span class="age${stale ? ' stale' : ''}" title="${p.source === 'git' ? 'Last commit' : p.source === 'mtime' ? 'Newest source file' : 'Unknown'}"><span class="sr-only">Last touched </span>${esc(ago(p.touched, now))}</span>
      <div class="acts">
        <span class="size">${fmt(p.bytes)}</span>
        <button class="btn small" data-pitems="${esc(p.path)}" aria-expanded="false" aria-controls="pitems-${i}" aria-label="Details for ${esc(p.display)}">Details</button>
        ${p.path ? `<button class="btn small" data-revealproject="${esc(p.path)}" aria-label="Reveal ${esc(p.display)}">Reveal</button>` : ''}
        ${canDel ? `<button class="btn small danger" data-delproject="${esc(p.path)}" aria-label="Delete ${esc(p.display)}">Delete</button>` : ''}
      </div>
      <div class="pitems" data-pitemsof="${esc(p.path)}" id="pitems-${i}" hidden>${p.items.map(it => `
        <div class="item">
          <span class="ipath" title="${esc(it.path)}">${esc(it.label)} — ${esc(it.path.startsWith(p.path + '/') ? it.path.slice(p.path.length + 1) : it.path)}</span>
          <span class="size${it.bytes ? '' : ' zero'}">${fmt(it.bytes)}</span>
          ${itemDeletable(entry(it.entryId)) ? `<button class="btn small danger" data-delitem="${it.entryId}" data-path="${esc(it.path)}" aria-label="Delete ${esc(it.path)}">Delete</button>` : '<span></span>'}
        </div>`).join('')}</div>
    </div>`;
  }).join('');
}
async function confirmAndDeleteProject(path) {
  if (state.deleting) return;
  const g = groupByProject(state.projects, projectEntries(), state.items).find(x => x.path === path);
  if (!g) return;
  const items = g.items.filter(it => itemDeletable(entry(it.entryId)));
  if (!items.length) return;
  $('#dlgTitle').textContent = `Delete the build output of ${g.display}?`;
  $('#dlgText').textContent = `About ${fmt(items.reduce((a, it) => a + it.bytes, 0))} across ${items.length} item${items.length === 1 ? '' : 's'} will be removed. Your source files stay; the next build recreates the rest. This can't be undone.`;
  $('#dlgOk').textContent = 'Delete';
  $('#dlgList').innerHTML = items.map(it => `<li>${esc(it.label)} — ${esc(it.path)} — ${fmt(it.bytes)}</li>`).join('');
  if (!await confirmDialog($('#dlg'))) return;
  const prow = document.querySelector(`.prow[data-project="${CSS.escape(path)}"]`), psize = prow?.querySelector('.acts .size');
  const btn = $('#deleteSel'), verb = 'Deleting';
  btn.setAttribute('aria-busy', 'true'); state.deleting = true; setBusy(prow, psize, true);
  try {
  for (const [i, it] of items.entries()) {
    btn.textContent = deletingLabel(i + 1, items.length, verb);
    announce(`${verb} ${it.path}`);
    log(`deleting ${it.path}…`);
    try {
      const r = await bridge.call('delete', { id: it.entryId, item: it.path });
      log(`  freed ${fmt(r.freedBytes ?? it.bytes)} — ${it.path}`, 'ok');
      state.items.set(it.entryId, (state.items.get(it.entryId) || []).filter(x => itemId(x) !== it.path));
      state.size.set(it.entryId, Math.max(0, (state.size.get(it.entryId) || 0) - it.bytes));
      const el = document.querySelector(`[data-size="${it.entryId}"]`); if (el) { el.textContent = fmt(state.size.get(it.entryId)); el.className = 'size' + (state.size.get(it.entryId) ? '' : ' zero'); }
      if (state.items.has(it.entryId) && document.querySelector(`[data-infoout="${it.entryId}"]`)) renderItems(it.entryId);
    } catch (err) { log(`  failed — ${it.path}: ${err.message}`, 'err'); }
  }
  } finally { state.deleting = false; setBusy(prow, psize, false); btn.removeAttribute('aria-busy'); btn.textContent = 'Delete selected'; }
  announce(`${g.display}: build output deleted`);
  updateTotals(); renderProjects(); refreshDisk();
}

// Footer panel: Log. (About is a dialog; the app menu and __openAbout open it.)
document.querySelector('.tabs').onclick = e => {
  const b = e.target.closest('button'); if (!b) return;
  const open = !b.classList.contains('on');
  document.querySelectorAll('.tabs button').forEach(x => { const on = open && x === b; x.classList.toggle('on', on); x.setAttribute('aria-expanded', String(on)); $('#' + x.dataset.panel).hidden = !on; });
  if (open && b.dataset.panel === 'log') { const p = $('#log'); p.scrollTop = p.scrollHeight; }
};
// About: a modal card (Escape closes it), opened from the app menu's About Backspacer.
window.__openAbout = () => { const d = $('#about'); if (!d.open) { d.showModal(); d.querySelector('.card').focus(); } };   // focus the card, not the × — no ring until Tab
$('#aboutClose').onclick = () => $('#about').close();
$('#fdaBtn').onclick = () => bridge.call('openFDA');
$('#clearSel').onclick = () => { state.selected.clear(); document.querySelectorAll('[data-sel],[data-selall]').forEach(c => c.checked = false); updateTotals(); };
document.addEventListener('change', e => {
  const id = e.target.dataset.sel, b = e.target.dataset.selall;
  if (id) { e.target.checked ? state.selected.add(id) : state.selected.delete(id); updateTotals(); }
  if (b) { document.querySelectorAll(`section[data-bucket="${b}"] .row:not([hidden]) [data-sel]`).forEach(c => { c.checked = e.target.checked; c.checked ? state.selected.add(c.dataset.sel) : state.selected.delete(c.dataset.sel); }); updateTotals(); }
});
// Mouse-down policy: the header is a window drag region (the bridge calls performDrag); anywhere
// else that isn't selectable text or a control, the default is suppressed so a drag can't sweep
// a selection across the paths (R17 made them selectable) — copy a path by dragging inside it.
const SELECTABLE_OR_INTERACTIVE = 'button, input, select, textarea, a, label, summary, dialog, [tabindex], .path, .ipath, .info-out, .panel';
document.addEventListener('mousedown', e => {
  if (e.button !== 0 || e.target.closest(SELECTABLE_OR_INTERACTIVE)) return;
  e.preventDefault();   // no selection sweep
  // Drag regions: the header, and the bare page around it — the title-bar strip above it in
  // particular, which is body padding under the transparent title bar.
  if (e.target.closest('header') || e.target === document.body || e.target === document.documentElement) bridge.call('dragWindow').catch(() => {});
});

// Right-click: tell the bridge which row (entry id) or Details item (its selector) is under the
// pointer, before WebKit asks for the menu; the native menu then offers a path action for it.
document.addEventListener('contextmenu', e => {
  const row = e.target.closest('.row[data-id]'); if (!row) return;
  const item = e.target.closest('.item[data-item]');
  bridge.call('contextTarget', { id: row.dataset.id, item: item ? item.dataset.item : null }).catch(() => {});
});

document.addEventListener('click', async e => {
  const head = e.target.closest('.bucket-head');
  if (head && !e.target.closest('.sel, .seg')) {   // "all" and the sort segment sit in the head without toggling it
    const sec = head.parentElement, open = sec.classList.toggle('collapsed') === false;
    head.querySelector('h2 button').setAttribute('aria-expanded', String(open));
    return;
  }
  const t = e.target.closest('button'); if (!t) return;
  if (t.dataset.info) {
    const id = t.dataset.info, out = document.querySelector(`[data-infoout="${id}"]`);
    if (!out.hidden) { out.hidden = true; t.setAttribute('aria-expanded', 'false'); return; }
    out.hidden = false; t.setAttribute('aria-expanded', 'true');
    if (state.items.has(id)) { renderItems(id); return; }
    out.innerHTML = explainHTML(entry(id), state.catalog.buckets) + '<pre>…</pre>';
    try { out.querySelector('pre').textContent = (await bridge.call('info', { id })).text || '(no output)'; } catch (err) { out.querySelector('pre').textContent = err.message; }
  }
  if (t.dataset.showsmall) { state.showSmall.add(t.dataset.showsmall); renderItems(t.dataset.showsmall); }
  if (t.dataset.reveal) bridge.call('reveal', { id: t.dataset.reveal }).catch(err => log(err.message, 'err'));
  if (t.dataset.del) confirmAndDelete([t.dataset.del]);
  if (t.dataset.delitem) confirmAndDeleteItem(t.dataset.delitem, t.dataset.path);
  if (t.dataset.delproject !== undefined) confirmAndDeleteProject(t.dataset.delproject);
  if (t.dataset.revealproject) bridge.call('revealProject', { path: t.dataset.revealproject }).catch(err => log(err.message, 'err'));
  if (t.dataset.pitems !== undefined) { const el = document.querySelector(`[data-pitemsof="${CSS.escape(t.dataset.pitems)}"]`); el.hidden = !el.hidden; t.setAttribute('aria-expanded', String(!el.hidden)); }
});
$('#deleteSel').onclick = () => confirmAndDelete([...state.selected]);

function entry(id) { return state.catalog.entries.find(e => e.id === id); }

// Granular entries (glob / paths / children): the Details panel lists every item with its
// size and, when the entry is deletable by path, its own Delete.
function renderItems(id) {
  const e = entry(id), out = document.querySelector(`[data-infoout="${id}"]`), items = state.items.get(id) || [];
  if (!items.length) { out.innerHTML = explainHTML(e, state.catalog.buckets) + '<pre>Nothing found.</pre>'; return; }
  items.sort((a, b) => (b.bytes || 0) - (a.bytes || 0));   // largest first; the host names them
  const show = itemName;
  const canDel = itemDeletable(e);
  // The size threshold applies here too; "show small" reveals the rest until the slider moves.
  const { shown, hidden, hiddenBytes } = state.showSmall.has(id) ? { shown: items, hidden: [], hiddenBytes: 0 } : splitItems(items, minBytes());
  const row = it => `
    <div class="item" data-item="${esc(itemId(it))}">
      <span class="ipath" title="${esc(it.path || it.key)}">${esc(show(it))}</span>
      <span class="size${it.bytes ? '' : ' zero'}">${fmt(it.bytes)}</span>
      ${canDel ? `<button class="btn small danger" data-delitem="${e.id}" data-path="${esc(itemId(it))}" aria-label="Delete ${esc(show(it))}">Delete</button>` : '<span></span>'}
    </div>`;
  const more = hidden.length ? `
    <div class="item more">
      <button class="btn small" data-showsmall="${e.id}">${hidden.length} smaller item${hidden.length === 1 ? '' : 's'}, ${fmt(hiddenBytes)} — below ${fmt(minBytes())}</button>
    </div>` : '';
  out.innerHTML = explainHTML(e, state.catalog.buckets) + shown.map(row).join('') + more;
}

async function confirmAndDeleteItem(id, path) {
  if (state.deleting) return;
  const e = entry(id), it = (state.items.get(id) || []).find(x => itemId(x) === path);
  if (!it || !itemDeletable(e)) return;
  const name = itemName(it);
  const trash = trashes(e) && !it.key;
  // The entry comes first: "~/Projects/enumerator" here is VS Code's storage *for* that project, not the project.
  $('#dlgTitle').textContent = trash ? `Move from ${e.label} to the Trash?` : `Delete from ${e.label}?`;
  $('#dlgText').textContent = `“${name}” — about ${fmt(it.bytes)} — ` + (trash ? 'will be moved to the Trash.' + TRASH_NOTE : "will be removed. This can't be undone.") + (e.sudo ? ' macOS will ask for your password.' : '');
  $('#dlgOk').textContent = trash ? 'Move to Trash' : 'Delete';
  $('#dlgList').innerHTML = `<li>${esc(it.key ? it.label : path)}</li>`;
  if (!await confirmDialog($('#dlg'))) return;
  const itemEl = document.querySelector(`[data-item="${CSS.escape(path)}"]`), itemSize = itemEl?.querySelector('.size');
  const verb = trash ? 'Moving' : 'Deleting';
  state.deleting = true; setBusy(itemEl, itemSize, true);
  announce(`${verb} ${name}`);
  log(`${trash ? 'moving to Trash' : 'deleting'} ${name}…`);
  try {
    const r = await bridge.call('delete', { id, item: path });
    log(`  ${r.trashed ? 'moved to Trash' : 'freed'} ${fmt(r.freedBytes ?? it.bytes)} — ${name}`, 'ok');
    announce(`${name}: ${r.trashed ? 'moved to Trash' : 'deleted'}, ${fmt(r.freedBytes ?? it.bytes)}`);
    state.items.set(id, (state.items.get(id) || []).filter(x => itemId(x) !== path));
    state.size.set(id, Math.max(0, (state.size.get(id) || 0) - it.bytes));
    const el = document.querySelector(`[data-size="${id}"]`); el.textContent = fmt(state.size.get(id)); el.className = 'size' + (state.size.get(id) ? '' : ' zero');
    renderItems(id); updateTotals(); renderProjects(); refreshDisk(); if (r.trashed) afterTrash();
  } catch (err) { log(`  failed — ${name}: ${err.message}`, 'err'); }
  finally { state.deleting = false; setBusy(itemEl, itemSize, false); }
}

async function confirmAndDelete(ids) {
  if (state.deleting) return;
  ids = ids.filter(id => deletable(entry(id)) && visible(id));
  if (!ids.length) return;
  const bytes = ids.reduce((a, id) => a + (ids.some(p => p !== id && (NEST.parent.get(id) === p)) ? 0 : state.size.get(id) || 0), 0);
  const needsAdmin = ids.some(id => entry(id).sudo);
  const toTrash = ids.filter(id => trashes(entry(id))).length, toRm = ids.length - toTrash;
  $('#dlgTitle').textContent = ids.length === 1 ? `${toTrash ? 'Move' : 'Delete'} “${entry(ids[0]).label}”${toTrash ? ' to the Trash' : ''}?` : `Delete ${ids.length} items?`;
  $('#dlgText').textContent = (toRm && toTrash ? `About ${fmt(bytes)}: ${toRm} removed permanently, ${toTrash} moved to the Trash.` + TRASH_NOTE
    : toTrash ? `About ${fmt(bytes)} will be moved to the Trash.` + TRASH_NOTE
    : `About ${fmt(bytes)} will be removed. This can't be undone.`) + (needsAdmin ? ' macOS will ask for your password for admin items.' : '');
  $('#dlgOk').textContent = toRm ? 'Delete' : 'Move to Trash';
  $('#dlgList').innerHTML = ids.map(id => `<li>${esc(entry(id).label)} — ${fmt(state.size.get(id))}</li>`).join('');
  if (!await confirmDialog($('#dlg'))) return;
  const btn = $('#deleteSel'); btn.setAttribute('aria-busy', 'true');
  state.deleting = true;
  try {
    for (const [i, id] of ids.entries()) {
      const e = entry(id); const row = document.querySelector(`.row[data-id="${id}"]`);
      const el = row.querySelector('[data-size]'), verb = trashes(e) ? 'Moving' : 'Deleting';
      btn.textContent = deletingLabel(i + 1, ids.length, verb);
      setBusy(row, el, true);
      announce(`${verb} ${e.label}`);   // at the start: the host reports nothing until it's done
      log(`${trashes(e) ? 'moving to Trash' : 'deleting'} ${e.label}…`);
      try {
        const r = await bridge.call('delete', { id });
        setBusy(row, el, false);
        log(`  ${r.trashed ? 'moved to Trash' : 'freed'} ${fmt(r.freedBytes ?? state.size.get(id))} — ${e.label}`, 'ok');
        announce(`${e.label}: ${r.trashed ? 'moved to Trash' : 'deleted'}, ${fmt(r.freedBytes ?? state.size.get(id))}`);
        state.size.set(id, 0); row.classList.add('done');
        el.textContent = rowSizeText(0, !!r.trashed); el.className = 'size zero';
        const cb = row.querySelector('[data-sel]'); if (cb) cb.checked = false; state.selected.delete(id);
      } catch (err) { setBusy(row, el, false); log(`  failed — ${e.label}: ${err.message}`, 'err'); }
      updateTotals();
    }
  } finally { state.deleting = false; btn.removeAttribute('aria-busy'); btn.textContent = 'Delete selected'; }
  updateTotals(); refreshDisk();
  if (ids.some(id => trashes(entry(id)))) afterTrash();
}

init().catch(err => { log('init: ' + err.message, 'err'); $('.tagline').textContent = 'failed to load catalog'; });
