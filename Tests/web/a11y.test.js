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
  assert.match(html, /<h3>Backspacer: get back your precious disk space<\/h3>/);
  assert.match(html, /\.row \.path \{[^}]*user-select: text/);
  assert.match(html, /\.sr-only \{/);
});

// ── contrast, computed from the tokens (WCAG relative luminance) ────────────────
const lum = ([r, g, b]) => { const ch = c => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; }; return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b); };
const ratio = (a, b) => { const [l1, l2] = [lum(a), lum(b)].sort((x, y) => y - x); return (l1 + 0.05) / (l2 + 0.05); };
const blend = (fg, alpha, bg) => fg.map((c, i) => c * alpha + bg[i] * (1 - alpha));
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const token = (block, name) => {
  const m = block.match(new RegExp(`${name}: (rgba\\(([^)]+)\\)|#[0-9a-f]{6})`));
  assert.ok(m, name);
  if (m[1].startsWith('#')) return { rgb: hex(m[1]), a: 1 };
  const [r, g, b, a] = m[2].split(',').map(Number); return { rgb: [r, g, b], a: a ?? 1 };
};
const contrast = (block, name, bg) => { const t = token(block, name); return ratio(blend(t.rgb, t.a, bg), bg); };

test('A7 muted and faint text meet contrast floors in every theme', () => {
  const glass = html.slice(html.indexOf('<style id="css-glass">'), html.indexOf('<style id="css-terminal">'));
  const light = glass.slice(0, glass.indexOf('@media (prefers-color-scheme: dark)'));
  const dark = glass.slice(glass.indexOf('@media (prefers-color-scheme: dark)'));
  const terminal = html.slice(html.indexOf('<style id="css-terminal">'));
  // panel backgrounds: the glass card over the light/dark mesh, the terminal panel
  const glassLightBg = [238, 241, 246], glassDarkBg = [42, 44, 51], terminalBg = hex('#0e1114');
  assert.ok(contrast(light, '--muted', glassLightBg) >= 4.5, 'glass light muted');
  assert.ok(contrast(light, '--faint', glassLightBg) >= 3.3, 'glass light faint');
  assert.ok(contrast(dark, '--muted', glassDarkBg) >= 4.5, 'glass dark muted');
  assert.ok(contrast(dark, '--faint', glassDarkBg) >= 4.5, 'glass dark faint');
  assert.ok(contrast(terminal, '--muted', terminalBg) >= 4.5, 'terminal muted');
  assert.ok(contrast(terminal, '--faint', terminalBg) >= 4.5, 'terminal faint');
  assert.equal((html.match(/@media \(prefers-contrast: more\)/g) || []).length, 2, 'a high-contrast block per theme');
});

test('A8 reduced motion is honoured', () => {
  assert.equal((html.match(/@media \(prefers-reduced-motion: reduce\)/g) || []).length, 2);
  assert.match(app, /matchMedia\('\(prefers-reduced-motion: reduce\)'\)/);
});

test('A9 the scrollbar is styled, not hidden', () => {
  const thumbs = html.match(/main::-webkit-scrollbar-thumb \{/g) || [];
  assert.ok(thumbs.length >= 2, 'a thumb rule in each theme (plus a dark-mode override in Glass)');
  assert.doesNotMatch(html, /::-webkit-scrollbar[^{]*\{[^}]*display: none/, 'the affordance stays visible');
  assert.doesNotMatch(html, /::-webkit-scrollbar[^{]*\{[^}]*width: 0/, 'the affordance stays visible');
});

test('A10 the header drags the window; selection only starts on selectable text', () => {
  assert.match(app, /addEventListener\('mousedown'/);
  assert.match(app, /bridge\.call\('dragWindow'\)/, 'a mouse-down on the header asks the window to follow');
  assert.match(app, /SELECTABLE_OR_INTERACTIVE = '[^']*\.path[^']*'/, 'paths stay selectable by dragging inside them');
  assert.match(app, /SELECTABLE_OR_INTERACTIVE = '[^']*input[^']*'/, 'controls keep their default mouse-down');
  assert.match(app, /e\.preventDefault\(\);\s*\/\/ no selection sweep/);
});
