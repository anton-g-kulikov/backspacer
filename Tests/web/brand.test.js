// Brand checks (ADR-20): the product is Backspacer everywhere a user or a build can see it,
// and the old name survives only where it is history. Run: node --test 'Tests/web/*.test.js'
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.join(__dirname, '../..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

test('K1 page title and wordmark', () => {
  const html = read('web/index.html');
  assert.match(html, /<title>Backspacer<\/title>/);
  assert.match(html, /<h1>Backspacer<\/h1>/, 'plain wordmark — no (y) in the app');
  assert.match(html, /<h3>Backspacer: get back your precious disk space<\/h3>/);
  assert.match(html, /The "Backspacer" name and icon are not licensed/);
  assert.doesNotMatch(html, /Reclaimer/);
});

test('K2 the page talks to Swift under the product name', () => {
  const app = read('web/app.js');
  assert.match(app, /messageHandlers\?\.backspacer\b/);
  assert.match(app, /window\.__backspacerReply = /);
  assert.match(app, /~\/Library\/Logs\/Backspacer\/Backspacer\.log/, 'the mock bridge reports the real log path');
  assert.doesNotMatch(app + read('web/logic.js') + read('web/boot.js'), /reclaimer/i);
});

test('K3 build script: app name and bundle id', () => {
  const sh = read('scripts/build-app.sh');
  assert.match(sh, /^APP_NAME="Backspacer"$/m);
  assert.match(sh, /^BUNDLE_ID="\$\{BUNDLE_ID:-com\.antonkulikov\.backspacer\}"$/m);
});

test('K4 notarize script: bundle, archives, volume and keychain profile', () => {
  const sh = read('scripts/notarize.sh');
  assert.match(sh, /^APP="build\/Backspacer\.app"$/m);
  assert.match(sh, /^PROFILE="\$\{PROFILE:-Backspacer\}"/m);
  assert.match(sh, /^ZIP="build\/Backspacer-\$VERSION\.zip"$/m);
  assert.match(sh, /^DMG="build\/Backspacer-\$VERSION\.dmg"$/m);
  assert.match(sh, /-volname "Backspacer"/);
});

test('K5 LICENSE reserves the new name; catalog leaves the new log folder alone', () => {
  assert.match(read('LICENSE'), /^Backspacer — Copyright/m);
  assert.match(read('LICENSE'), /The "Backspacer" name and the app icon are not licensed/);
  const logs = JSON.parse(read('catalog.json')).entries.find((e) => e.id === 'cache-logs');
  assert.deepEqual(logs.exclude, ['Backspacer', 'DiagnosticReports']);
});

test('K6 the old name is history only', () => {
  // Files where "Reclaimer" may still appear, and why. Anything else is a leak.
  const allowed = new Set([
    'CHANGELOG.md',                      // release history
    'README.md',                         // the "formerly Reclaimer" note
    '_meta/architecture-decisions.md',   // ADR-20 and the ADRs written under the old name
    '_meta/project-task-list.md',        // the Done log
    'Tests/web/brand.test.js',           // this file
    'Tests/web/site.test.js',            // asserts the old name is absent from the promo site
  ]);
  const out = execFileSync('git', ['grep', '-il', 'reclaimer', '--', '.'], { cwd: root, encoding: 'utf8' });
  const leaks = out.split('\n').filter(Boolean).filter((f) => !allowed.has(f));
  assert.deepEqual(leaks, [], 'files that still say Reclaimer');
});

test('K7 the tagline sits under the wordmark; scan verbs keep their own slot beside the name', () => {
  const html = read('web/index.html');
  assert.match(html, /<div class="text"><div class="name"><h1>Backspacer<\/h1><span class="sub" id="host">[^<]*<\/span><\/div><span class="tagline">I got some if you need it<\/span><\/div>/);
  assert.match(html, /\.brand \.text \{ display: flex; flex-direction: column;/, 'stacked: name row, then tagline');
  assert.doesNotMatch(html, /Pearl Jam|Got Some/, 'the line is a wink, not an attribution');
  const app = read('web/app.js');
  assert.match(app, /function updateTotals\(\) \{[\s\S]*?\$\('\.tagline'\)\.textContent = taglineText\(RECLAIMABLE\.reduce\(\(a, b\) => a \+ bucketTotal\(b\), 0\)\)/,
    'the counter follows the bucket badges and updates with every size');
});

test('K8 the app icon leads the header brand block and never drifts from the icon source', () => {
  const html = read('web/index.html');
  assert.match(html, /<div class="brand"><img class="mark" src="icon.svg" alt=""><div class="text">/, 'icon first, empty alt (the h1 is the name)');
  assert.equal(read('web/icon.svg'), read('assets/AppIcon.svg'), 'web/icon.svg is a copy of the icon source');
  assert.match(read('scripts/make-icon.sh'), /cp assets\/AppIcon\.svg web\/icon\.svg/, 'make-icon.sh refreshes the copy');
  assert.match(html, /\.brand \.mark \{[^}]*width: 42px/, 'a touch bigger than the two-line brand in Glass');
  assert.match(html, /\.brand \.mark \{ display: none; \}/, 'hidden in Terminal: a colour icon breaks the $ prompt idiom');
  assert.match(html, /img-src 'self'/, 'CSP lets the page load it');
});
