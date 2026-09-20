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
  assert.match(html, /<h2 id="aboutTitle">Backspacer<\/h2>/, "About's heading is the app name in a dialog");
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
  assert.match(app, /if \(e\.target\.closest\('header'\) \|\| e\.target === document\.body \|\| e\.target === document\.documentElement\) bridge\.call\('dragWindow'\)/, 'a mouse-down on the header or the bare page (the title-bar strip) asks the window to follow');
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
  assert.match(html, /grid-template-columns: 360px 1fr auto;/, 'Glass: fixed brand column | centred controls | button');
  assert.match(html, /grid-template-columns: 400px 1fr auto;/, 'Terminal: fixed, wider for the monospace tagline');
  assert.doesNotMatch(html, /grid-template-columns: minmax\(0, \d+px\) 1fr auto/, 'the brand column must not grow with the tagline — the centre would move');
  assert.equal((html.match(/\.controls \{[^}]*justify-self: center/g) || []).length, 2);
  assert.match(html, /#scan \{ justify-self: end; min-width: 11em; \}/, 'Glass: wider than the longest verb frame in the system font');
  assert.match(html, /#scan \{ justify-self: end; min-width: 22ch;/, 'Terminal: ch units — "[ investigating... ]" is 20 monospace characters');
  assert.equal((html.match(/main \{[^}]*overflow-y: scroll;/g) || []).length, 2, 'a permanent scrollbar track in both themes: the gutter never appears or disappears, so the header never shifts');
  assert.doesNotMatch(html, /scrollbar-gutter/, 'WebKit ignores it; overflow-y: scroll is the reservation');
  assert.match(app, /window\.addEventListener\('resize', syncGutter\);\nsyncGutter\(\);/, 'measured once at load');
  assert.match(app, /--sb', \(m\.offsetWidth - m\.clientWidth\) \+ 'px'/, '--sb is the full track width');
  assert.equal((html.match(/main \{[^}]*overflow-y: scroll; padding: [^;]* calc\(1[68]px \+ var\(--sb, 0px\)\); \}/g) || []).length, 2, 'the list pads its left by the track width, so its content lines up with the header and footer, which inset both sides by the same amount');
  const stacks = html.match(/@media \(max-width: 959px\) \{\s*header \{ grid-template-columns: 1fr auto; \}\s*\.brand \{ grid-column: 1 \/ -1; \}/g) || [];
  assert.equal(stacks.length, 2, 'below 960 px the header stacks: brand row, then controls + button, in both themes');
});

test('A13 About offers a manual update check with a live result', () => {
  assert.match(html, /<p class="upstate" id="updResult" aria-live="polite"><\/p>\s*<p class="upd"><button class="btn small" id="checkUpd">Check for updates<\/button><\/p>\s*<label class="opt">/, 'status line, then the button, then the opt-out — LensSense order');
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

test('A16 Sparkle drives the notice: the page shows what the updater found and routes both controls to it', () => {
  assert.match(html, /<div class="tabs">\s*<button data-panel="log"[^>]*>Log<\/button>\s*<span class="notice" id="updNotice" hidden><\/span>\s*<\/div>/, 'the footer is Log plus the update notice — About is a dialog now');
  assert.match(html, /<label class="opt"><input type="checkbox" id="autoUpd" checked>Check for updates automatically<\/label>/);
  assert.match(app, /window\.__updateFound = /, 'Sparkle → page: a newer version was found');
  assert.match(app, /bridge\.call\('checkUpdate'\)/, 'page → Sparkle: the manual check');
  assert.match(app, /prefSet', \{ key: 'autoUpdateCheck'/);
  assert.doesNotMatch(app, /autoCheckUpdate/, 'the page no longer polls');
  assert.doesNotMatch(app, /api\.github\.com/);
});

test('A17 About is a proper dialog: centred card, close button, Escape, opened from the app menu', () => {
  assert.match(html, /<dialog id="about" class="about" aria-labelledby="aboutTitle">\s*<button class="close" id="aboutClose" aria-label="Close">/);
  assert.match(html, /<img class="mark" src="icon.svg" alt="">\s*<h2 id="aboutTitle">Backspacer<\/h2>\s*<p class="ver">Version <span id="aboutVersion"><\/span><\/p>/, 'icon, name, version — top of the card');
  assert.match(html, /<p class="help">Need help\? <a href="mailto:anton\.g\.kulikov@gmail\.com">/);
  assert.match(html, /<button class="btn small" id="revealLog">Reveal log<\/button>/);
  assert.match(html, /<a href="https:\/\/github\.com\/anton-g-kulikov\/backspacer\/blob\/main\/LICENSE">License<\/a>/);
  assert.doesNotMatch(html, /data-panel="about"/, 'no About tab in the footer');
  assert.equal((html.match(/\.tabs button \{ border: 0; background: none;/g) || []).length, 2, 'the Log tab stays a text tab (▸ Log), not a button pill, in both themes');
  assert.equal((html.match(/\.tabs button::before \{ content: "▸ "; \}/g) || []).length, 2);
  assert.equal((html.match(/#log \.err \{ color: var\(--danger\); \}/g) || []).length, 2, 'the Log panel keeps its styling');
  assert.equal((html.match(/dialog\.about \{/g) || []).length, 2, 'the card is styled in both themes');
  assert.match(app, /window\.__openAbout = \(\) => \{ const d = \$\('#about'\); if \(!d\.open\) \{ d\.showModal\(\); d\.querySelector\('\.card'\)\.focus\(\); \} \};/, 'modal (Escape closes); focus lands on the card so the × shows no ring until Tab');
  assert.match(html, /<div class="card" tabindex="-1">/);
  assert.match(app, /\$\('#aboutClose'\)\.onclick = \(\) => \$\('#about'\)\.close\(\)/);
});

test('A18 Glass: the list scrolls under a frosted header and footer; the overlap is measured, not guessed', () => {
  const glass = html.slice(html.indexOf('<style id="css-glass">'), html.indexOf('</style>', html.indexOf('<style id="css-glass">')));
  assert.match(glass, /header \{[^}]*position: absolute; top: 0; left: 0; right: 0;/);
  assert.match(glass, /footer \{[^}]*position: absolute; bottom: 0; left: 0; right: 0;/);
  assert.match(glass, /main \{[^}]*padding: var\(--header-h, 0px\) 16px var\(--footer-h, 0px\) calc\(16px \+ var\(--sb, 0px\)\)/, 'the list pads by the bars\' heights');
  assert.match(glass, /--band: rgba\(255,255,255,\.[0-9]+\)/);
  assert.match(glass, /backdrop-filter: blur\(\d+px\)[^;]*;\n\s+display: grid; grid-template-columns/, 'the header is frosted so what scrolls beneath shows through');
  assert.match(app, /new ResizeObserver\(syncBars\)/, 'header and footer heights are observed (stacked header, Log panel open)');
  assert.match(app, /--header-h', .*offsetHeight/);
});

test('A19 the by-project view: a toggle in the Project folders island, one card, rows per project with age and their own Reveal/Delete', () => {
  assert.match(html, /<div class="seg" id="projView"[^>]*>\s*<button data-view="tool" aria-pressed="true">By tool<\/button><button data-view="project" aria-pressed="false">By project<\/button>/);
  assert.match(html, /<section class="bucket projects" id="projects" hidden>/);
  assert.match(app, /bridge\.call\('projects'\)/);
  assert.match(app, /groupByProject\(state\.projects, projectEntries\(\), state\.items\)/);
  assert.match(app, /data-delproject="\$\{esc\(p\.path\)\}"/, 'per-project delete carries the project path as the key');
  assert.match(app, /data-revealproject="\$\{esc\(p\.path\)\}"/);
  assert.match(app, /bridge\.call\('revealProject', \{ path/, 'reveal goes through a validated op, not a page-named path');
  assert.match(app, /bridge\.call\('delete', \{ id: it\.entryId, item: it\.path \}\)/, 'per-project delete is the existing per-item delete, one validated call per item');
  assert.match(app, /prefSet', \{ key: 'projectView'/);
  assert.match(app, /aria-label="Last touched \$\{[^}]+\}"/, 'the age has an accessible name');
});

test('A20 in the by-project view the project entries leave the buckets and live in the card only', () => {
  assert.match(app, /const visible = id => isVisible\(state\.size\.get\(id\), minBytes\(\)\) && !\(state\.projectView === 'project' && isProjectEntry\(id\)\)/, 'rows, select-all and bucket badges all follow visible()');
  assert.match(app, /const projectBytes = state\.projectView === 'project' \?/, 'the tagline still counts the bytes the card took over');
  assert.match(app, /if \(state\.catalog\) updateTotals\(\);\s*\/\/ applyThreshold hides or restores/);
});
