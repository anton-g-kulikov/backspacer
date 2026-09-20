// axe-core over the page as it actually renders. jsdom loads web/index.html with the
// mock bridge (the same one a plain browser gets), the harness drives the page into each
// state a user reaches, and axe must report zero violations. Contrast is not judged here
// (jsdom has no layout; A7 computes it from the tokens). Run: node --test Tests/web/axe.test.js
// Needs `npm ci` once (axe-core, jsdom — the only Node dependencies in the repo).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, ResourceLoader } = require('jsdom');
const axe = require('axe-core');

const WEB = path.join(__dirname, '../../web');
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, '../../catalog.json'), 'utf8'));

// Scripts come from disk; the origin is http so localStorage works (file: is opaque).
class Local extends ResourceLoader {
  fetch(url) { return Promise.resolve(fs.readFileSync(path.join(WEB, new URL(url).pathname.replace(/^\/web\//, '')))); }
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function until(fn, what, ms = 8000) {
  const t0 = Date.now();
  while (!fn()) { if (Date.now() - t0 > ms) throw new Error('timed out waiting for ' + what); await sleep(20); }
}

async function page() {
  const dom = new JSDOM(fs.readFileSync(path.join(WEB, 'index.html'), 'utf8'), {
    url: 'http://localhost/web/index.html', runScripts: 'dangerously', resources: new Local(), pretendToBeVisual: true,
    beforeParse(w) {
      w.fetch = async () => ({ json: async () => catalog });                          // the mock's catalog fetch
      w.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
      w.ResizeObserver = class { observe() {} disconnect() {} };
      const st = w.setTimeout; w.setTimeout = (f, ms, ...a) => st(f, Math.min(ms || 0, 5), ...a);   // the mock's fake latency, compressed
      w.HTMLElement.prototype.scrollIntoView = () => {};
      if (!w.HTMLDialogElement.prototype.showModal) {                                  // older jsdom
        w.HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', ''); };
        w.HTMLDialogElement.prototype.close = function (v) { this.returnValue = v; this.removeAttribute('open'); this.dispatchEvent(new w.Event('close')); };
      }
    },
  });
  const w = dom.window, d = w.document;
  await until(() => d.querySelectorAll('#buckets .row').length > 0, 'the catalog to render');
  w.eval(axe.source);
  return { w, d, dom };
}

async function violations(w, context = w.document) {
  const r = await w.axe.run(context, { rules: { 'color-contrast': { enabled: false } }, resultTypes: ['violations'] });
  return Array.from(r.violations, v => `${v.id}: ${v.help}\n` + Array.from(v.nodes, n => '    ' + n.target.join(' ') + ' — ' + n.failureSummary.split('\n')[1]).join('\n'));
}
const clean = async (w, ctx) => { const v = await violations(w, ctx); assert.equal(v.length, 0, v.join('\n')); };

test('A21 the page as first rendered, then scanned, has no axe violations', async () => {
  const { w, d } = await page();
  await clean(w);
  d.querySelector('#scan').click();
  await until(() => d.querySelector('#scan').getAttribute('aria-busy') === 'false' && d.querySelector('[data-size].pending') === null, 'the scan to finish');
  await clean(w);
});

test('A22 every bucket open, a Details panel open, the Log open', async () => {
  const { w, d } = await page();
  d.querySelector('#scan').click();
  await until(() => d.querySelector('#scan').getAttribute('aria-busy') === 'false', 'the scan');
  for (const b of d.querySelectorAll('.bucket-head h2 button[aria-expanded="false"]')) b.click();
  const info = d.querySelector('[data-info]'); info.click();
  await until(() => !d.querySelector(`[data-infoout="${info.dataset.info}"]`).hidden, 'the Details panel');
  d.querySelector('[data-panel="log"]').click();
  await sleep(30);
  assert.equal(d.querySelectorAll('.bucket.collapsed').length, 0, 'all buckets open');
  await clean(w);
});

test('A23 the by-project view', async () => {
  const { w, d } = await page();
  d.querySelector('#scan').click();
  await until(() => d.querySelector('#scan').getAttribute('aria-busy') === 'false', 'the scan');
  d.querySelector('[data-view="project"]').click();
  await until(() => d.querySelector('#projects') && !d.querySelector('#projects').hidden, 'the Projects card');
  await clean(w);
});

test('A24 the confirmation dialog and About, while open', async () => {
  const { w, d } = await page();
  d.querySelector('#scan').click();
  await until(() => d.querySelector('#scan').getAttribute('aria-busy') === 'false', 'the scan');
  // a row the size filter shows (the mock sizes at random; hidden rows are not deletable)
  d.querySelector('.row:not([hidden]) input[data-sel]').click();
  d.querySelector('#deleteSel').click();
  await until(() => d.querySelector('#dlg').open, 'the confirmation dialog');
  await clean(w);
  d.querySelector('#dlg button[value="cancel"]').click(); d.querySelector('#dlg').close('cancel');
  w.__openAbout();
  await until(() => d.querySelector('#about').open, 'About');
  await clean(w);
});

test('A25 the harness sees violations (a guard against an axe run that checks nothing)', async () => {
  const { w, d } = await page();
  d.querySelector('#buckets').insertAdjacentHTML('beforeend', '<img src="x.png"><button></button>');
  const v = await violations(w);
  assert.ok(v.some(x => x.startsWith('image-alt:')), v.join('\n'));
  assert.ok(v.some(x => x.startsWith('button-name:')), v.join('\n'));
});
