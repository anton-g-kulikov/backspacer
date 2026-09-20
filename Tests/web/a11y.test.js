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
  const thumbs = html.match(/main::-webkit-scrollbar-thumb, \.info-out::-webkit-scrollbar-thumb, \.panel::-webkit-scrollbar-thumb \{/g) || [];
  assert.ok(thumbs.length >= 2, 'one thumb rule per theme covering every scrolling container: the list, Details and the Log/About panels');
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

test('A11 right-click names the row or item by selector only; the bridge resolves the path', () => {
  assert.match(app, /addEventListener\('contextmenu'/);
  assert.match(app, /bridge\.call\('contextTarget', \{ id[^}]*item[^}]*\}\)/);
  assert.match(app, /<div class="item" data-item="\$\{esc\(itemId\(it\)\)\}">/, 'Details items carry their selector');
  assert.doesNotMatch(app, /contextTarget', \{[^}]*path:/, 'never a path from the page (ADR-10)');
});

test('A12 the scan verbs run inside the Scan button; theme and size controls sit centred', () => {
  assert.match(app, /function startScanWords\(\) \{[\s\S]*?\$\('#scan'\)\.textContent = scanFrame\(0, words\)/);
  assert.match(app, /reduced-motion: reduce\)'\)\.matches\) \{ \$\('#scan'\)\.textContent = 'Scanning…'/, 'static label under Reduce Motion');
  assert.doesNotMatch(app, /#host/, 'nothing writes to a slot that no longer exists');
  assert.match(html, /<\/div>\s*<button class="btn primary" id="scan">Scan<\/button>\s*<div class="disk">/, 'the button is its own grid cell after .controls');
  assert.match(html, /grid-template-columns: minmax\(0, 360px\) 1fr auto;/, 'Glass: brand | centred controls | button');
  assert.match(html, /grid-template-columns: minmax\(0, 400px\) 1fr auto;/, 'Terminal: the monospace tagline needs a wider brand column');
  assert.equal((html.match(/\.controls \{[^}]*justify-self: center/g) || []).length, 2);
  assert.equal((html.match(/#scan\[aria-busy="true"\] \{[^}]*min-width/g) || []).length, 2, 'the button keeps a steady width while the verbs cycle');
  const stacks = html.match(/@media \(max-width: 959px\) \{\s*header \{ grid-template-columns: 1fr auto; \}\s*\.brand \{ grid-column: 1 \/ -1; \}/g) || [];
  assert.equal(stacks.length, 2, 'below 960 px the header stacks: brand row, then controls + button, in both themes');
});

test('A13 About offers a manual update check with a live result', () => {
  assert.match(html, /<p class="upd"><button class="btn small" id="checkUpd">Check for updates<\/button>/, 'its own line, not squeezed into the credits');
  assert.match(html, /<span id="updResult" aria-live="polite"><\/span>/);
  assert.match(app, /\$\('#checkUpd'\)\.onclick = /);
  assert.match(app, /bridge\.call\('checkUpdate'\)/);
  assert.match(app, /window\.__checkUpdates = /, 'the app menu triggers the same check');
  assert.doesNotMatch(app, /checkUpdate'\)[^;]*\n[^\n]*init\(/, 'never at launch — only on the click');
});

test('A14 Details lists honour the size threshold and say what they hide', () => {
  assert.match(app, /function renderItems\(id\) \{[\s\S]*?splitItems\(items, minBytes\(\)\)/);
  assert.match(app, /<button class="btn small" data-showsmall="\$\{e\.id\}">/, 'the summary row is a button that reveals the small items');
  assert.match(app, /smaller item/, 'it says how many and how much');
  assert.match(app, /function applyThreshold\(\) \{[\s\S]*?renderItems\(/, 'open Details lists re-render when the slider moves');
});

test('A15 the size filter defaults to 10 MB (the slider\'s first stop) unless a preference says otherwise', () => {
  assert.match(app, /const state = \{[^}]*thr: 0,/);
  assert.match(html, /<input type="range" id="thr" min="0" max="9" value="0" [^>]*aria-valuetext="10 MB">/);
  assert.match(html, /<b id="thrLbl">10 MB<\/b>/);
});

test('A16 a quiet automatic update check after the first scan, with a footer notice and an opt-out', () => {
  assert.match(html, /<div class="tabs">\s*<button data-panel="log"[^>]*>Log<\/button>\s*<span class="notice" id="updNotice" hidden><\/span>\s*<button data-panel="about"/, 'the notice sits between Log and About');
  assert.match(html, /<label class="opt"><input type="checkbox" id="autoUpd" checked> Check for updates automatically<\/label>/);
  assert.match(app, /bridge\.call\('autoCheckUpdate'\)/);
  assert.match(app, /if \(!state\.autoChecked\) \{ state\.autoChecked = true; autoCheckUpdates\(\); \}/, 'once per session, after the scan finishes');
  assert.doesNotMatch(app, /init\(\)[\s\S]{0,400}autoCheckUpdate/, 'not at launch');
  assert.match(app, /prefSet', \{ key: 'autoUpdateCheck'/);
});
