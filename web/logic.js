/* ═══════════════════════════════════════════════════════════════════
   Reclaimer — pure page logic. No DOM, no state: everything here takes
   its inputs as arguments so it can run under Node (Tests/web) as well
   as in the page. index.html binds these to its state.
   ═══════════════════════════════════════════════════════════════════ */

const ORDER = ['safe', 'regen', 'decide', 'keep', 'locked'];
const DELETABLE_BUCKETS = ['safe', 'regen', 'decide'];
/** Size-threshold stops for the "Show ≥" slider. */
const THR = [10e6, 20e6, 50e6, 100e6, 200e6, 500e6, 1e9, 2e9, 5e9, 10e9];

const fmt = b => b == null ? '—' : b < 1e6 ? `${(b / 1e3).toFixed(0)} KB` : b < 1e9 ? `${(b / 1e6).toFixed(0)} MB` : `${+(b / 1e9).toFixed(1)} GB`;
const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

/** Whole-entry delete: a deletable bucket, not manual, and something to remove. */
const deletable = e => DELETABLE_BUCKETS.includes(e.bucket) && !e.manual && !!(e.path || e.paths || e.glob || e.deleteCmd);
/** Resolves to several items the user can act on one at a time. */
const granular = e => !!(e.glob || e.paths || e.children || e.itemsCmd);
/** Has something to show under Details. */
const hasInfo = e => !!(e.infoCmd || e.path || e.paths || e.glob || e.itemsCmd);
/** Items can be removed one at a time: by path (rm) or by the entry's deleteItemCmd. */
const itemDeletable = e => DELETABLE_BUCKETS.includes(e.bucket) && !e.manual && (!!e.deleteItemCmd || (deletable(e) && !e.deleteCmd && !e.itemsCmd));
const itemId = it => it.key ?? it.path;
/** Mirrors Bridge.disposal: Your-call folders go to the Trash; caches, admin paths and command-driven entries are removed for good. */
const trashes = e => e.bucket === 'decide' && !e.sudo && !e.deleteCmd && !e.itemsCmd;
/** What an item is called in the Details list. */
const itemName = it => it.display ?? it.label ?? it.path.split('/').slice(-2).join('/');

/** The size cell: a row moved to the Trash says so instead of showing 0. */
const rowSizeText = (bytes, trashed) => trashed ? 'in Trash' : fmt(bytes);
/** Rows measured below the threshold are hidden; rows still measuring stay visible. */
const isVisible = (bytes, minBytes) => bytes == null || bytes >= minBytes;

/**
 * Some entries live inside others (pip cache inside ~/Library/Caches). Returns direct
 * parent/child links from the catalog's static paths so totals can count each byte once.
 */
function buildNesting(entries) {
  const P = e => e.path ? [e.path] : (e.paths || []);
  const inside = (a, b) => a === b || a.startsWith(b.replace(/\/$/, '') + '/');
  const within = (c, p) => P(c).length && P(p).length && P(c).every(cp => P(p).some(pp => inside(cp, pp)));
  const nest = { children: new Map(), parent: new Map() };
  for (const p of entries) {
    const kids = entries.filter(c => c !== p && within(c, p) && !entries.some(q => q !== p && q !== c && within(c, q) && within(q, p)));
    nest.children.set(p.id, kids.map(k => k.id));
    for (const k of kids) nest.parent.set(k.id, p.id);
  }
  return nest;
}
/** Measured size minus direct nested children, never negative. */
const ownSize = (id, sizes, nest) => Math.max(0, (sizes.get(id) || 0) - (nest.children.get(id) || []).reduce((a, c) => a + (sizes.get(c) || 0), 0));
/** True when any ancestor entry is selected (its deletion already covers this one). */
const hasSelectedParent = (id, selected, nest) => { for (let p = nest.parent.get(id); p; p = nest.parent.get(p)) if (selected.has(p)) return true; return false; };

/**
 * Disk meter segments, left to right: everything else, then the buckets from least to
 * most deletable, so the reclaimable green sits next to the free space.
 */
function meterSegments(disk, bytesByBucket, buckets) {
  const acc = ORDER.reduce((a, b) => a + (bytesByBucket[b] || 0), 0);
  return [
    { seg: 'other', bytes: Math.max(0, disk.used - acc), title: 'Everything else' },
    ...[...ORDER].reverse().map(b => ({ seg: b, bytes: bytesByBucket[b] || 0, title: buckets[b]?.title || b })),
  ];
}

/** Concurrent size requests during a scan. With the bridge's 2-way du for multi-path entries that
 *  caps a scan at 8 du processes — noticeable on an SSD, not a strain on the machine. */
const SCAN_WORKERS = 4;
/** Longest-known-first: the slow entries start first so no 16-second du begins when everything else is done. */
const scanOrder = (entries, durations) => entries
  .map((e, i) => ({ e, i, d: durations[e.id] ?? -1 }))
  .sort((a, b) => b.d - a.d || a.i - b.i)
  .map(x => x.e);

/** What the header says while a scan runs, Claude-Code style: a rotating verb with breathing dots. */
const SCAN_WORDS = ['measuring', 'surveying', 'investigating', 'rummaging', 'sniffing', 'excavating', 'swooping', 'dowsing'];
/** A fresh order for each scan (Fisher–Yates; `rng` is injectable for tests). */
const shuffled = (words, rng = Math.random) => { const a = [...words]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
/** Frame `tick` (≈ every 250 ms): the verb changes every 8 ticks, the dots every tick. */
const scanFrame = (tick, words = SCAN_WORDS) => words[Math.floor(tick / 8) % words.length] + '.'.repeat(tick % 4);

/**
 * Opens a <dialog> and resolves true only if it closed with returnValue "ok". The stale value
 * is reset first: Escape closes a dialog without touching returnValue, so without the reset a
 * previous "ok" would confirm the next delete (R1).
 */
function confirmDialog(dlg) {
  dlg.returnValue = '';
  return new Promise(resolve => {
    dlg.addEventListener('close', () => resolve(dlg.returnValue === 'ok'), { once: true });
    dlg.showModal();
  });
}

if (typeof module !== 'undefined') {
  module.exports = { ORDER, THR, SCAN_WORKERS, scanOrder, SCAN_WORDS, shuffled, scanFrame, rowSizeText, confirmDialog, fmt, esc, deletable, granular, hasInfo, itemDeletable, itemId, trashes, itemName, isVisible, buildNesting, ownSize, hasSelectedParent, meterSegments };
}
