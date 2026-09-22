// Run: node --test Tests/web
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const L = require('../../web/logic.js');
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, '../../catalog.json'), 'utf8'));
const E = (bucket, extra = {}) => ({ id: 'x', group: 'g', bucket, label: 'L', path: '~/x', ...extra });

test('J1 fmt', () => {
  assert.equal(L.fmt(null), '—');
  assert.equal(L.fmt(512e3), '512 KB');
  assert.equal(L.fmt(5e6), '5 MB');
  assert.equal(L.fmt(1.5e9), '1.5 GB');
  assert.equal(L.fmt(2e9), '2 GB');
});

test('J2 esc', () => {
  assert.equal(L.esc(`a & <b> "c" 'd'`), 'a &amp; &lt;b&gt; &quot;c&quot; &#39;d&#39;');
  assert.equal(L.esc('plain/path with spaces'), 'plain/path with spaces');
});

test('J3 deletable / itemDeletable / trashes mirror Bridge.disposal', () => {
  assert.equal(L.trashes(E('decide')), true);
  assert.equal(L.trashes(E('safe')), false);
  assert.equal(L.trashes(E('regen')), false);
  assert.equal(L.trashes(E('decide', { sudo: true })), false);
  assert.equal(L.trashes(E('decide', { deleteCmd: 'x' })), false);
  assert.equal(L.trashes(E('decide', { itemsCmd: 'x', deleteItemCmd: 'y {key}' })), false);
  assert.equal(L.deletable(E('safe', { manual: true })), false);
  assert.equal(L.deletable(E('keep')), false);
  assert.equal(L.deletable(E('locked')), false);
  const runtimes = { id: 'r', group: 'g', bucket: 'decide', label: 'R', itemsCmd: 'ls', deleteItemCmd: 'rm {key}' };
  assert.equal(L.deletable(runtimes), false, 'no whole-entry delete without a path or deleteCmd');
  assert.equal(L.itemDeletable(runtimes), true, 'but items are');
  assert.equal(L.itemDeletable(E('safe', { deleteCmd: 'x', paths: ['a', 'b'] })), false, 'a command entry is never per-item by path');
});

test('J4 buildNesting on the shipped catalog', () => {
  const nest = L.buildNesting(catalog.entries);
  assert.deepEqual([...nest.children.get('cache-user')].sort(), ['cache-brew', 'regen-pip', 'regen-pods', 'regen-yarn']);
  for (const c of ['cache-brew', 'regen-pip']) assert.equal(nest.parent.get(c), 'cache-user');
  // a grandchild is a direct child of its parent only
  const entries = [
    { id: 'a', path: '~/a' }, { id: 'b', path: '~/a/b' }, { id: 'c', path: '~/a/b/c' },
  ].map(e => ({ group: 'g', bucket: 'safe', label: e.id, ...e }));
  const n = L.buildNesting(entries);
  assert.deepEqual(n.children.get('a'), ['b']);
  assert.deepEqual(n.children.get('b'), ['c']);
  assert.equal(n.parent.get('c'), 'b');
});

test('J5 ownSize and hasSelectedParent', () => {
  const entries = [{ id: 'a', path: '~/a' }, { id: 'b', path: '~/a/b' }, { id: 'c', path: '~/a/b/c' }]
    .map(e => ({ group: 'g', bucket: 'safe', label: e.id, ...e }));
  const nest = L.buildNesting(entries);
  const sizes = new Map([['a', 100], ['b', 60], ['c', 10]]);
  assert.equal(L.ownSize('a', sizes, nest), 40);
  assert.equal(L.ownSize('b', sizes, nest), 50);
  assert.equal(L.ownSize('c', sizes, nest), 10);
  assert.equal(L.ownSize('a', new Map([['a', 10], ['b', 60]]), nest), 0, 'never negative');
  assert.equal(L.hasSelectedParent('c', new Set(['a']), nest), true, 'grandparent counts');
  assert.equal(L.hasSelectedParent('c', new Set(['b']), nest), true);
  assert.equal(L.hasSelectedParent('a', new Set(['b', 'c']), nest), false);
});

test('J6 isVisible', () => {
  assert.equal(L.isVisible(null, 100e6), true);
  assert.equal(L.isVisible(undefined, 100e6), true);
  assert.equal(L.isVisible(99e6, 100e6), false);
  assert.equal(L.isVisible(100e6, 100e6), true);
});

test('J7 meterSegments', () => {
  const segs = L.meterSegments({ size: 1000, used: 700 }, { safe: 100, regen: 50, decide: 200, keep: 20, locked: 30 }, catalog.buckets);
  assert.deepEqual(segs.map(s => s.seg), ['other', 'locked', 'keep', 'decide', 'regen', 'safe']);
  assert.equal(segs[0].bytes, 300);
  assert.equal(segs.find(s => s.seg === 'safe').title, 'Safe to delete');
  const over = L.meterSegments({ size: 1000, used: 100 }, { safe: 500, regen: 0, decide: 0, keep: 0, locked: 0 }, catalog.buckets);
  assert.equal(over[0].bytes, 0, 'other floored at zero');
});

test('J8 itemName', () => {
  assert.equal(L.itemName({ path: '/a/b/c', display: 'shown' }), 'shown');
  assert.equal(L.itemName({ key: 'k', label: 'iPhone' }), 'iPhone');
  assert.equal(L.itemName({ path: '/Users/x/Projects/app/node_modules' }), 'app/node_modules');
});

test('J9 catalog consistency', () => {
  for (const e of catalog.entries) {
    if (e.itemsCmd) { assert.ok(L.granular(e), e.id); assert.ok(L.hasInfo(e), e.id); }
    if (e.children) assert.ok(L.granular(e), e.id);
  }
});

test('J10 scanFrame rotates words and breathes dots', () => {
  assert.equal(L.scanFrame(0), 'measuring');
  assert.equal(L.scanFrame(1), 'measuring.');
  assert.equal(L.scanFrame(3), 'measuring...');
  assert.equal(L.scanFrame(4), 'measuring', 'dots go back to none');
  assert.equal(L.scanFrame(8), 'surveying');
  assert.equal(new Set(L.SCAN_WORDS).size, L.SCAN_WORDS.length, 'no duplicates');
  assert.ok(L.SCAN_WORDS.length >= 3 && L.SCAN_WORDS.length <= 8);
  assert.equal(L.scanFrame(8 * L.SCAN_WORDS.length), 'measuring', 'wraps around');
});

test('J11 shuffled is a permutation, order depends on the rng', () => {
  const a = L.shuffled(L.SCAN_WORDS, () => 0);
  const b = L.shuffled(L.SCAN_WORDS, () => 0.999);
  assert.deepEqual([...a].sort(), [...L.SCAN_WORDS].sort());
  assert.deepEqual([...b].sort(), [...L.SCAN_WORDS].sort());
  assert.notDeepEqual(a, b);
  assert.equal(L.scanFrame(1, ['zebra', 'apple']), 'zebra.');
  assert.equal(L.scanFrame(8, ['zebra', 'apple']), 'apple');
});

test('J12 rowSizeText', () => {
  assert.equal(L.rowSizeText(5e6, false), '5 MB');
  assert.equal(L.rowSizeText(0, true), 'in Trash');
  assert.equal(L.rowSizeText(null, false), '—');
});

test('J13 scanOrder puts the slow ones first', () => {
  const entries = ['a', 'b', 'c', 'd'].map(id => ({ id }));
  const order = L.scanOrder(entries, { b: 16000, d: 300, a: 50 }).map(e => e.id);
  assert.deepEqual(order, ['b', 'd', 'a', 'c']);
  assert.deepEqual(L.scanOrder(entries, {}).map(e => e.id), ['a', 'b', 'c', 'd'], 'no hints: catalog order');
  assert.equal(L.SCAN_WORKERS, 4);
});

// A <dialog> stand-in with the spec's behaviour: close(value) sets returnValue, Escape closes without.
function fakeDialog() {
  const listeners = [];
  return {
    returnValue: '', open: false,
    showModal() { this.open = true; },
    addEventListener(type, fn) { if (type === 'close') listeners.push(fn); },
    close(value) { if (value !== undefined) this.returnValue = value; this.open = false; listeners.splice(0).forEach(fn => fn()); },
  };
}

test('J14 confirmDialog: Escape after a real Delete does not confirm (R1)', async () => {
  const dlg = fakeDialog();
  const first = L.confirmDialog(dlg); assert.equal(dlg.open, true); dlg.close('ok');
  assert.equal(await first, true);
  const second = L.confirmDialog(dlg); dlg.close();          // Escape: no value
  assert.equal(await second, false);
  const third = L.confirmDialog(dlg); dlg.close('cancel');
  assert.equal(await third, false);
});

test('J15 hostile folder names cannot break out of an attribute (R2)', () => {
  const hostile = 'x" onmouseover="alert(1)';
  const escaped = L.esc(hostile);
  assert.ok(!escaped.includes('"'));
  // what the browser gives back from data-path="…" is the original string, nothing more
  const html = fs.readFileSync(path.join(__dirname, '../../web/index.html'), 'utf8');
  assert.match(html, /<meta http-equiv="Content-Security-Policy" content="[^"]*script-src 'self'[^"]*">/);
  assert.ok(!/<script>/.test(html) && !/<script[^>]*>[^<]*\S[^<]*<\/script>/.test(html), 'no inline script blocks');
  assert.ok(!/ on[a-z]+=/.test(html), 'no inline event handlers in the markup');
});

test('J16 rowSizeText says what an unknown size means on an FDA entry', () => {
  assert.equal(L.rowSizeText(null, false, true), 'needs access');
  assert.equal(L.rowSizeText(null, false, false), '—');
  assert.equal(L.rowSizeText(5e6, false, true), '5 MB');
});

test('J17 taglineText: the reclaimable total sits inside the tagline as an aside', () => {
  const { taglineText, RECLAIMABLE } = require('../../web/logic.js');
  assert.equal(taglineText(0), 'I got some if you need it', 'nothing measured yet: the plain line');
  assert.equal(taglineText(undefined), 'I got some if you need it');
  assert.equal(taglineText(35.9e9), 'I got some [35.9 GB of space] if you need it');
  assert.equal(taglineText(689e6), 'I got some [689 MB of space] if you need it');
  assert.deepEqual(RECLAIMABLE, ['safe', 'regen', 'decide'], 'Keep and Managed by macOS never count');
});

test('J19 splitItems: the size threshold applies to Details items, unknown sizes stay visible', () => {
  const { splitItems } = require('../../web/logic.js');
  const items = [{ path: 'a', bytes: 500e6 }, { path: 'b', bytes: 99e6 }, { path: 'c', bytes: 100e6 }, { path: 'd' }, { path: 'e', bytes: 0 }];
  const r = splitItems(items, 100e6);
  assert.deepEqual(r.shown.map((i) => i.path), ['a', 'c', 'd'], 'at or above the threshold, or unmeasured');
  assert.deepEqual(r.hidden.map((i) => i.path), ['b', 'e']);
  assert.equal(r.hiddenBytes, 99e6);
  assert.deepEqual(splitItems(items, 0).hidden, [], 'a zero threshold hides nothing');
});

test('J20 groupByProject: build-output items fold into their project by longest path prefix; the rest is "elsewhere"; stalest first', () => {
  const { groupByProject } = require('../../web/logic.js');
  const projects = [
    { path: '/h/Projects/alpha', display: '~/Projects/alpha', touched: 1789000000, source: 'git' },
    { path: '/h/Projects/beta', display: '~/Projects/beta', touched: 1700000000, source: 'mtime' },
    { path: '/h/Projects/beta/nested', display: '~/Projects/beta/nested', touched: null, source: null },
  ];
  const entries = [{ id: 'nm', label: 'node_modules' }, { id: 'next', label: '.next cache' }];
  const items = new Map([
    ['nm', [{ path: '/h/Projects/alpha/node_modules', bytes: 2e9 }, { path: '/h/Projects/beta/nested/node_modules', bytes: 5e8 }, { path: '/h/Projects/beta/node_modules', bytes: 1e9 }, { path: '/h/elsewhere/node_modules', bytes: 1e8 }]],
    ['next', [{ path: '/h/Projects/alpha/.next/cache', bytes: 3e8 }]],
  ]);
  const g = groupByProject(projects, entries, items);
  assert.deepEqual(g.map((x) => x.display), ['~/Projects/beta', '~/Projects/alpha', '~/Projects/beta/nested', 'Elsewhere'], 'oldest first, unknown dates after known, elsewhere last');
  const alpha = g.find((x) => x.display === '~/Projects/alpha');
  assert.equal(alpha.bytes, 2.3e9);
  assert.deepEqual(alpha.items.map((i) => [i.entryId, i.label, i.name, i.bytes]), [['nm', 'node_modules', 'node_modules', 2e9], ['next', '.next cache', 'cache', 3e8]], 'largest first, labelled by entry, named by folder');
  assert.equal(g.find((x) => x.display === '~/Projects/beta/nested').items[0].path, '/h/Projects/beta/nested/node_modules', 'longest prefix wins');
  assert.equal(g.find((x) => x.display === '~/Projects/beta').items.length, 1);
  assert.equal(g.find((x) => x.display === 'Elsewhere').bytes, 1e8);
  assert.deepEqual(groupByProject(projects, entries, new Map()), [], 'nothing measured, nothing to show');
});

test('J21 ago: how long since a project was touched, in words', () => {
  const { ago } = require('../../web/logic.js');
  const now = 1_800_000_000;
  assert.equal(ago(null, now), 'never measured');
  assert.equal(ago(now - 3600, now), 'today');
  assert.equal(ago(now - 86400 * 1.5, now), 'yesterday');
  assert.equal(ago(now - 86400 * 5, now), '5 days ago');
  assert.equal(ago(now - 86400 * 20, now), '3 weeks ago');
  assert.equal(ago(now - 86400 * 70, now), '2 months ago');
  assert.equal(ago(now - 86400 * 400, now), 'a year ago');
  assert.equal(ago(now - 86400 * 800, now), '2 years ago');
});

test('J22 explainHTML: the reasoning block Details opens with — labelled lines, only the ones present, escaped', () => {
  const { explainHTML, hasInfo } = L;
  const e = { id: 'x', bucket: 'safe', explain: { what: 'Build <b>intermediates</b>.', why: 'Rebuilt by the next build.', after: 'One slow build.', keep: 'Mid-build.' } };
  const h = explainHTML(e, { safe: { title: 'Safe to delete' } });
  assert.match(h, /^<dl class="explain">/);
  assert.match(h, /<dt>What<\/dt><dd>Build &lt;b&gt;intermediates&lt;\/b&gt;\.<\/dd>/);
  assert.match(h, /<dt>Why Safe to delete<\/dt><dd>Rebuilt by the next build\.<\/dd>/);
  assert.match(h, /<dt>After deleting<\/dt><dd>One slow build\.<\/dd>/);
  assert.match(h, /<dt>Keep if<\/dt><dd>Mid-build\.<\/dd>/);
  const partial = explainHTML({ bucket: 'keep', explain: { what: 'Swap.', why: 'In use.' } }, { keep: { title: 'Keep' } });
  assert.doesNotMatch(partial, /After deleting|Keep if/);
  assert.match(partial, /Why Keep/);
  assert.equal(explainHTML({ bucket: 'safe' }, {}), '', 'no block without explain');
  assert.ok(hasInfo({ explain: { what: 'a', why: 'b' } }), 'explain alone earns a Details button');
});

test('J23 sortProjects: by age keeps groupByProject\'s order; by size is largest first; Elsewhere stays last either way', () => {
  const { sortProjects } = L;
  const g = [{ path: '/a', bytes: 1, touched: 10 }, { path: '/b', bytes: 3, touched: 20 }, { path: '', bytes: 9, touched: null }, { path: '/c', bytes: 2, touched: 30 }];
  assert.deepEqual(sortProjects(g, 'age').map(x => x.path), ['/a', '/b', '', '/c'], 'age: untouched, the input order is the age order');
  assert.deepEqual(sortProjects(g, 'size').map(x => x.path), ['/b', '/c', '/a', ''], 'size: largest first, Elsewhere last');
  assert.deepEqual(g.map(x => x.path), ['/a', '/b', '', '/c'], 'the input is not mutated');
  assert.deepEqual(sortProjects(g, 'bogus').map(x => x.path), ['/a', '/b', '', '/c'], 'anything else means age');
});

test('J24 deletingLabel: which item is in flight, only when there are several', () => {
  const { deletingLabel } = L;
  assert.equal(deletingLabel(1, 1), 'Deleting…');
  assert.equal(deletingLabel(2, 5), 'Deleting 2 of 5…');
  assert.equal(deletingLabel(1, 3, 'Moving'), 'Moving 1 of 3…');
  assert.equal(deletingLabel(1, 1, 'Moving'), 'Moving…');
});
