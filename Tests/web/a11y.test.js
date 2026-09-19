// Static accessibility checks over the page templates. Run: node --test 'Tests/web/*.test.js'
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname, '../../web/index.html'), 'utf8');
const app = fs.readFileSync(path.join(__dirname, '../../web/app.js'), 'utf8');

test('A1 bucket headers are real buttons with expanded state', () => {
  assert.match(app, /<h2><button[^>]*aria-expanded="\$\{[^}]+\}"[^>]*aria-controls="bucket-\$\{b\}"/);
  assert.match(app, /id="bucket-\$\{b\}"/, 'the controlled region has the id');
  assert.match(app, /setAttribute\('aria-expanded'/);
});

test('A2 controls have accessible names', () => {
  assert.match(app, /data-sel="\$\{e\.id\}" aria-label="\$\{esc\(e\.label\)\}"/);
  assert.match(app, /data-selall="\$\{b\}" aria-label="Select all in \$\{esc\(meta\.title\)\}"/);
  assert.match(app, /data-removeroot="[^"]*" aria-label="Stop searching \$\{esc\(r\.display\)\}"/);
});

test('A3 the slider announces a size, not an index', () => {
  assert.match(html, /<input type="range" id="thr"[^>]*aria-label="[^"]+"/);
  assert.match(app, /\$\('#thr'\)\.setAttribute\('aria-valuetext', fmt\(minBytes\(\)\)\)/);
});

test('A4 a live region announces scan and delete outcomes; Scan is never disabled', () => {
  assert.match(html, /<div id="live" class="sr-only" aria-live="polite"/);
  assert.match(html, /<pre id="log" class="panel" role="log"/);
  assert.match(app, /function announce\(/);
  assert.ok((app.match(/announce\(/g) || []).length >= 4, 'scan start, scan end, delete, item delete');
  assert.doesNotMatch(app, /\$\('#scan'\)\.disabled = true/);
  assert.match(app, /\$\('#scan'\)\.setAttribute\('aria-busy'/);
});

test('A5 the disk meter has a text alternative', () => {
  assert.match(html, /<div class="bar" id="diskBar" role="img"/);
  assert.match(app, /bar\.setAttribute\('aria-label'/);
});

test('A6 disclosure and toggle states, dialog labelling, focus, badges, headings, selection', () => {
  assert.match(app, /data-info="\$\{e\.id\}" aria-expanded="false" aria-controls="info-\$\{e\.id\}"/);
  assert.match(app, /t\.setAttribute\('aria-expanded'/);
  assert.match(html, /<button data-panel="log" aria-expanded="false" aria-controls="log">/);
  assert.match(html, /<button data-theme="glass" aria-pressed="/);
  assert.match(app, /b\.setAttribute\('aria-pressed'/);
  assert.match(html, /<dialog id="dlg" aria-labelledby="dlgTitle" aria-describedby="dlgText">/);
  assert.ok((html.match(/:focus-visible \{/g) || []).length >= 2, 'a focus ring in each theme');
  assert.doesNotMatch(html, /\.badge \{[^}]*font-size: 10px/);
  assert.match(html, /<h3>Reclaimer: get back your precious disk space<\/h3>/);
  assert.match(html, /\.row \.path \{[^}]*user-select: text/);
  assert.match(html, /\.sr-only \{/);
});
