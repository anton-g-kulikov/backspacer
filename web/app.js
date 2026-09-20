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
        case 'catalog': catalog ??= await (await fetch('../catalog.json')).json(); return catalog;
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
              s.items = Array.from({ length: n }, (_, i) => ({ path: e.paths ? e.paths[i % e.paths.length] + (i >= e.paths.length ? '-' + i : '') : `${base}${i + 1}/${e.glob ? e.glob.name : 'item-' + (i + 1)}`, bytes: 0 }));
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
        case 'checkUpdate': case 'autoCheckUpdate': return { current: 'dev', latest: '0.9.0', newer: true, url: 'https://github.com/anton-g-kulikov/backspacer/releases/latest' };
        case 'projectRoots': return { roots: roots.map(r => ({ path: r, display: r })) };
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
const state = { catalog: null, size: new Map(), items: new Map(), selected: new Set(), showSmall: new Set(), autoChecked: false, scanning: false, scanned: false, thr: 0, disk: null, roots: [] };
// fmt, esc, deletable, granular, hasInfo, itemDeletable, itemId, trashes, itemName, isVisible,
// buildNesting, ownSize, hasSelectedParent, meterSegments, ORDER, THR come from logic.js.
const TRASH_NOTE = ' Put it back from Finder if you change your mind; empty the Trash to actually free the space.';
const afterTrash = () => { const t = state.catalog.entries.find(e => e.id === 'cache-trash'); if (t) scan([t]); };
// Rows measured below the current stop are hidden, deselected and left out of totals.
const minBytes = () => THR[state.thr];
const visible = id => isVisible(state.size.get(id), minBytes());

// Totals use each entry's *own* size (measured minus nested children) so nothing counts twice.
let NEST = { children: new Map(), parent: new Map() };
const own = id => ownSize(id, state.size, NEST);
const selectedParent = id => hasSelectedParent(id, state.selected, NEST);
/** Screen-reader announcements for things that otherwise only change visually. */
function announce(text) { const l = $('#live'); l.textContent = ''; setTimeout(() => { l.textContent = text; }, 50); }
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
  requestAnimationFrame(syncGutter);
}
window.__setTheme = t => { applyTheme(t); bridge.call('prefSet', { key: 'theme', value: t }).catch(() => {}); };
// Scrollbar gutter: the scroll area reserves it on both edges; the floating/full-width bars
// widen their side margins by the same amount so all three columns line up.
function syncGutter() { const m = document.querySelector('main'); document.documentElement.style.setProperty('--sb', ((m.offsetWidth - m.clientWidth) / 2) + 'px'); }
window.addEventListener('resize', syncGutter);
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
  bridge.call('appInfo').then(r => { $('#aboutVersion').textContent = r.version; $('#aboutVersion').title = 'build ' + r.build; }).catch(() => {});
  bridge.call('logPath').then(r => { $('#logPath').textContent = r.path.replace(/^\/Users\/[^/]+/, '~'); }).catch(() => {});
  $('#revealLog').onclick = () => bridge.call('revealLog').catch(err => log(err.message, 'err'));
  // Update check: only ever on the click (or the app menu), never at launch — no phoning home.
  window.__checkUpdates = async () => {
    const out = $('#updResult'); out.textContent = 'Checking…';
    let r = null, err = null;
    try { r = await bridge.call('checkUpdate'); } catch (e) { err = e.message; log('update check: ' + e.message, 'err'); }
    const u = updateText(r, err);
    out.textContent = u.text + ' ';
    if (u.link) { const a = document.createElement('a'); a.href = u.link; a.textContent = u.linkText; out.appendChild(a); }
  };
  $('#checkUpd').onclick = () => { window.__checkUpdates(); };
  bridge.call('prefGet', { key: 'autoUpdateCheck' }).then(r => { $('#autoUpd').checked = r.value !== '0'; }).catch(() => {});
  $('#autoUpd').onchange = e => bridge.call('prefSet', { key: 'autoUpdateCheck', value: e.target.checked ? '1' : '0' }).catch(() => {});
  state.catalog = await bridge.call('catalog');
  NEST = buildNesting(state.catalog.entries);
  render(); syncGutter();
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
    const anyDel = entries.some(deletable);
    sec.innerHTML = `
      <div class="bucket-head">
        <span class="dot" style="background:var(--${b})"></span>
        <h2><button type="button" aria-expanded="${!collapsed}" aria-controls="bucket-${b}">${meta.title}</button><small>${meta.blurb}</small></h2>
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
            ${hasInfo(e) ? `<button class="btn small" data-info="${e.id}" aria-expanded="false" aria-controls="info-${e.id}">Details</button>` : '<span></span>'}
            ${(e.path || e.paths) ? `<button class="btn small" data-reveal="${e.id}">Reveal</button>` : '<span></span>'}
            ${canDel ? `<button class="btn small danger" data-del="${e.id}">Delete</button>` : '<span></span>'}
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
  if (!state.autoChecked) { state.autoChecked = true; autoCheckUpdates(); }
  stopScanWords();   // no "reclaimable" total — how much to reclaim is the user's call
  log('scan complete');
}

const bucketTotal = b => state.catalog.entries.filter(e => e.bucket === b && visible(e.id)).reduce((a, e) => a + own(e.id), 0);
function updateTotals() {
  applyThreshold(); updateMeter();
  for (const b of ORDER) { const el = document.querySelector(`[data-total="${b}"]`); if (el) el.textContent = fmt(bucketTotal(b)); }
  $('.tagline').textContent = taglineText(RECLAIMABLE.reduce((a, b) => a + bucketTotal(b), 0));
  const n = state.selected.size, bytes = [...state.selected].reduce((a, id) => a + (selectedParent(id) ? 0 : state.size.get(id) || 0), 0);
  $('#sum').innerHTML = n ? `<b>${n}</b> selected · <b>${fmt(bytes)}</b>` : 'Nothing selected';
  $('#deleteSel').disabled = !n;
}

function applyThreshold() {
  state.showSmall.clear();
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
// The quiet check: once per session, after the first scan (never at launch, never in the way).
// The bridge throttles it to one request a day and honours the opt-out; only a newer version shows.
async function autoCheckUpdates() {
  let r; try { r = await bridge.call('autoCheckUpdate'); } catch { return; }
  if (!r || r.skipped || !r.newer) return;
  const u = updateText(r);
  const notice = $('#updNotice'); notice.textContent = u.text + ' ';
  const a = document.createElement('a'); a.href = u.link; a.textContent = u.linkText; notice.appendChild(a);
  notice.hidden = false;
  const out = $('#updResult'); out.textContent = u.text + ' '; out.appendChild(a.cloneNode(true));
}
function stopScanWords() { clearInterval(scanTimer); scanTimer = null; updateScanBtn(); }
// While scanning the button carries the verbs (startScanWords); at rest it says what a click does.
function updateScanBtn() { $('#scan').textContent = state.scanning ? 'Scanning…' : state.scanned ? 'Rescan' : 'Scan'; }
$('#scan').onclick = () => scan();
$('#thr').oninput = e => setThreshold(e.target.value, true);
// Footer panels: Log (left) and About (right); one open at a time.
document.querySelector('.tabs').onclick = e => {
  const b = e.target.closest('button'); if (!b) return;
  const open = !b.classList.contains('on');
  document.querySelectorAll('.tabs button').forEach(x => { const on = open && x === b; x.classList.toggle('on', on); x.setAttribute('aria-expanded', String(on)); $('#' + x.dataset.panel).hidden = !on; });
  if (open && b.dataset.panel === 'log') { const p = $('#log'); p.scrollTop = p.scrollHeight; }
};
// The app menu's Check for Updates… lands in About, where the result is shown.
window.__openAbout = () => { const b = document.querySelector('.tabs button[data-panel="about"]'); if (!b.classList.contains('on')) b.click(); };
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
  if (e.target.closest('header')) bridge.call('dragWindow').catch(() => {});
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
  if (head && !e.target.closest('.sel')) {
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
    out.innerHTML = '<pre>…</pre>';
    try { out.querySelector('pre').textContent = (await bridge.call('info', { id })).text || '(no output)'; } catch (err) { out.querySelector('pre').textContent = err.message; }
  }
  if (t.dataset.showsmall) { state.showSmall.add(t.dataset.showsmall); renderItems(t.dataset.showsmall); }
  if (t.dataset.reveal) bridge.call('reveal', { id: t.dataset.reveal }).catch(err => log(err.message, 'err'));
  if (t.dataset.del) confirmAndDelete([t.dataset.del]);
  if (t.dataset.delitem) confirmAndDeleteItem(t.dataset.delitem, t.dataset.path);
});
$('#deleteSel').onclick = () => confirmAndDelete([...state.selected]);

function entry(id) { return state.catalog.entries.find(e => e.id === id); }

// Granular entries (glob / paths / children): the Details panel lists every item with its
// size and, when the entry is deletable by path, its own Delete.
function renderItems(id) {
  const e = entry(id), out = document.querySelector(`[data-infoout="${id}"]`), items = state.items.get(id) || [];
  if (!items.length) { out.innerHTML = '<pre>Nothing found.</pre>'; return; }
  items.sort((a, b) => (b.bytes || 0) - (a.bytes || 0));   // largest first; the host names them
  const show = itemName;
  const canDel = itemDeletable(e);
  // The size threshold applies here too; "show small" reveals the rest until the slider moves.
  const { shown, hidden, hiddenBytes } = state.showSmall.has(id) ? { shown: items, hidden: [], hiddenBytes: 0 } : splitItems(items, minBytes());
  const row = it => `
    <div class="item" data-item="${esc(itemId(it))}">
      <span class="ipath" title="${esc(it.path || it.key)}">${esc(show(it))}</span>
      <span class="size${it.bytes ? '' : ' zero'}">${fmt(it.bytes)}</span>
      ${canDel ? `<button class="btn small danger" data-delitem="${e.id}" data-path="${esc(itemId(it))}">Delete</button>` : '<span></span>'}
    </div>`;
  const more = hidden.length ? `
    <div class="item more">
      <button class="btn small" data-showsmall="${e.id}">${hidden.length} smaller item${hidden.length === 1 ? '' : 's'}, ${fmt(hiddenBytes)} — below ${fmt(minBytes())}</button>
    </div>` : '';
  out.innerHTML = shown.map(row).join('') + more;
}

async function confirmAndDeleteItem(id, path) {
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
  log(`${trash ? 'moving to Trash' : 'deleting'} ${name}…`);
  try {
    const r = await bridge.call('delete', { id, item: path });
    log(`  ${r.trashed ? 'moved to Trash' : 'freed'} ${fmt(r.freedBytes ?? it.bytes)} — ${name}`, 'ok');
    announce(`${name}: ${r.trashed ? 'moved to Trash' : 'deleted'}, ${fmt(r.freedBytes ?? it.bytes)}`);
    state.items.set(id, (state.items.get(id) || []).filter(x => itemId(x) !== path));
    state.size.set(id, Math.max(0, (state.size.get(id) || 0) - it.bytes));
    const el = document.querySelector(`[data-size="${id}"]`); el.textContent = fmt(state.size.get(id)); el.className = 'size' + (state.size.get(id) ? '' : ' zero');
    renderItems(id); updateTotals(); refreshDisk(); if (r.trashed) afterTrash();
  } catch (err) { log(`  failed — ${name}: ${err.message}`, 'err'); }
}

async function confirmAndDelete(ids) {
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
  for (const id of ids) {
    const e = entry(id); const row = document.querySelector(`.row[data-id="${id}"]`);
    log(`${trashes(e) ? 'moving to Trash' : 'deleting'} ${e.label}…`);
    try {
      const r = await bridge.call('delete', { id });
      log(`  ${r.trashed ? 'moved to Trash' : 'freed'} ${fmt(r.freedBytes ?? state.size.get(id))} — ${e.label}`, 'ok');
      announce(`${e.label}: ${r.trashed ? 'moved to Trash' : 'deleted'}, ${fmt(r.freedBytes ?? state.size.get(id))}`);
      state.size.set(id, 0); row.classList.add('done');
      const el = row.querySelector('[data-size]'); el.textContent = rowSizeText(0, !!r.trashed); el.className = 'size zero';
      const cb = row.querySelector('[data-sel]'); if (cb) cb.checked = false; state.selected.delete(id);
    } catch (err) { log(`  failed — ${e.label}: ${err.message}`, 'err'); }
    updateTotals();
  }
  refreshDisk();
  if (ids.some(id => trashes(entry(id)))) afterTrash();
}

init().catch(err => { log('init: ' + err.message, 'err'); $('.tagline').textContent = 'failed to load catalog'; });
