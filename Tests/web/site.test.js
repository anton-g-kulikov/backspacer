// Static checks over the promo site (site/index.html, published by GitHub Pages).
// Run: node --test 'Tests/web/*.test.js'
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '../..');
const sitePath = path.join(root, 'site/index.html');
// Until site/index.html exists the suite skips (CI stays green while the page is queued);
// SITE_REQUIRED=1 turns skipping into failure — the Pages workflow sets it.
const exists = fs.existsSync(sitePath);
const html = exists ? fs.readFileSync(sitePath, 'utf8') : '';
const gate = { skip: !exists && !process.env.SITE_REQUIRED && 'site/index.html not built yet' };
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'catalog.json'), 'utf8'));
const text = html.replace(/<style[\s\S]*?<\/style>|<script[\s\S]*?<\/script>/g, '').replace(/<[^>]+>/g, ' ');
const unesc = s => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");

test('W1 the page exists with the head every crawler and share card needs', gate, () => {
  assert.ok(html.length > 0, 'site/index.html exists');
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<meta charset="utf-8">/);
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
  assert.match(html, /<title>Backspacer[^<]*<\/title>/);
  assert.match(html, /<meta name="description" content="[^"]{60,}">/);
  for (const p of ['og:title', 'og:description', 'og:image', 'og:url', 'twitter:card']) {
    assert.match(html, new RegExp(`<meta (?:property|name)="${p}" content="[^"]+">`), p);
  }
  assert.match(html, /<link rel="icon"/);
  assert.match(html, /<meta http-equiv="Content-Security-Policy" content="default-src 'none';/);
});

test('W2 every local asset the page references exists under site/', gate, () => {
  const refs = [...html.matchAll(/\b(?:src|href|srcset)="([^"]+)"/g)].map(m => m[1])
    .flatMap(v => v.split(',').map(s => s.trim().split(' ')[0]))
    .filter(v => v && !/^(https?:|mailto:|#|data:)/.test(v))
    .map(v => v.replace(/\?.*$/, ''));   // ?v= cache-busters
  assert.ok(refs.length >= 4, 'the page references local assets (icon, screenshots)');
  for (const r of refs) assert.ok(fs.existsSync(path.join(root, 'site', r)), `missing site/${r}`);
  const og = html.match(/property="og:image" content="https:\/\/backspacer\.dev\/([^"]+)"/);
  assert.ok(og && fs.existsSync(path.join(root, 'site', og[1])), 'og:image is a site file on the canonical host');
});

test('W3 download and source links go to the GitHub repo', gate, () => {
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/backspacer\/releases\/latest"/);
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/backspacer"/);
  assert.match(html, /api\.github\.com\/repos\/anton-g-kulikov\/backspacer\/releases\/latest/, 'the version badge is fetched live');
  assert.match(html, /<a class="btn primary" href="https:\/\/github\.com\/anton-g-kulikov\/backspacer\/releases\/latest" id="download" download>/, 'no-JS fallback is the release page');
  assert.match(html, /browser_download_url/, 'with JS the button points at the DMG asset itself');
  assert.match(html, /\.href = dmg\.browser_download_url/, 'the href is rewritten, not opened by script');
  assert.match(html, /<a class="notes" href="https:\/\/github\.com\/anton-g-kulikov\/backspacer\/releases\/latest">Release notes<\/a>/, 'the release page stays one link away');
});

test('W4 the bucket names and blurbs are the catalog\'s, verbatim', gate, () => {
  for (const b of Object.values(catalog.buckets)) {
    assert.ok(unesc(text).includes(b.title), `bucket title "${b.title}"`);
    assert.ok(unesc(text).includes(b.blurb), `bucket blurb "${b.blurb}"`);
  }
});

test('W5 every catalog group the page names is a real group, and the entry count is current', gate, () => {
  const groups = new Set(catalog.entries.map(e => e.group));
  const named = [...html.matchAll(/data-group="([^"]+)"/g)].map(m => unesc(m[1]));
  assert.ok(named.length >= 8, 'the "what it finds" section lists catalog groups');
  for (const g of named) assert.ok(groups.has(g), `"${g}" is not a catalog group`);
  assert.match(text, new RegExp(`\\b${catalog.entries.length} entries\\b`), 'entry count matches catalog.json');
});

test('W6 license wording follows ADR-14: noncommercial, never "open source"', gate, () => {
  assert.doesNotMatch(text, /open[- ]source/i);
  assert.match(text, /free for noncommercial use/i);
  assert.match(html, /href="https:\/\/polyformproject\.org\/licenses\/noncommercial\/1\.0\.0"/);
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/backspacer\/blob\/main\/LICENSE"/);
});

test('W7 accessibility basics: landmarks, one h1, skip link, alt text, named controls, motion and contrast', gate, () => {
  assert.equal((html.match(/<h1[\s>]/g) || []).length, 1);
  assert.match(html, /<a class="skip" href="#main">/);
  assert.match(html, /<main id="main">/);
  assert.match(html, /<nav aria-label="[^"]+">/);
  for (const img of html.match(/<img\b[^>]*>/g) || []) assert.match(img, /\balt="/, img);
  for (const b of html.match(/<button\b[^>]*>/g) || []) assert.match(b, /aria-(pressed|label|controls)="/, b);
  assert.match(html, /:focus-visible\s*\{/);
  assert.match(html, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(html, /@media \(prefers-color-scheme: dark\)/);
  assert.match(html, /\.hero-grid > \*, \.two > \*[^{]*\{ min-width: 0; \}/, 'grid items may shrink so <pre> blocks scroll instead of widening the page');
});

test('W8 the wordmark is plain Backspacer, no (y) device, and the old name appears nowhere', gate, () => {
  assert.match(html, /<h1>Backspacer<\/h1>/);
  assert.doesNotMatch(text, /\(y\)|\(y\/n\)/, 'the (y) device was dropped with the app\'s wordmark');
  assert.doesNotMatch(text, /Reclaimer(?!y)/, 'the old name appears nowhere on the site');
});

test('W10 the tagline is the one Pearl Jam nod: under the h1, in og:description, and nowhere else', gate, () => {
  assert.match(html, /<\/h1>\s*<p class="tagline">I got some if you need it\.<\/p>/);
  assert.match(html, /<meta property="og:description" content="I got some if you need it\. [^"]+">/);
  assert.equal((text.match(/I got some if you need it/g) || []).length, 1, 'once in the body');
  assert.doesNotMatch(text, /Pearl Jam|Got Some/, 'the site never names the band or the track');
});

test('W11 the CSP hashes match the inline style and script blocks', gate, () => {
  const { createHash } = require('node:crypto');
  const sha = x => 'sha256-' + createHash('sha256').update(x).digest('base64');
  const block = tag => html.match(new RegExp(`<${tag}(?![^>]*application/ld\\+json)[^>]*>([\\s\\S]*?)</${tag}>`))[1];   // JSON-LD is data
  const csp = html.match(/Content-Security-Policy" content="([^"]+)"/)[1];
  for (const m of html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)) assert.ok(csp.includes(`'${sha(m[1])}'`), 'style hash (run node scripts/site-csp.mjs)');
  assert.ok(csp.includes(`script-src '${sha(block('script'))}'`), 'script hash (run node scripts/site-csp.mjs)');
  assert.equal((html.match(/<style/g) || []).length, 2, 'glass + terminal sheets'); assert.equal((html.match(/<script(?! type="application\/ld\+json")/g) || []).length, 1, 'one executable script (JSON-LD is data)');
  assert.doesNotMatch(html, /\bon[a-z]+="/, 'no inline event handlers (CSP would block them)');
  assert.doesNotMatch(html, /\sstyle="/, 'no style attributes (a hashed style-src blocks them)');
  assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
});

test('W12 look switcher: Glass / Terminal like the app, persisted, applied before first paint, screenshot follows', gate, () => {
  const group = html.match(/<div class="skins" role="group" aria-label="Look">([\s\S]*?)<\/div>/);
  assert.ok(group, 'a labelled group in the header');
  for (const t of ['glass', 'terminal']) assert.match(group[1], new RegExp(`<button type="button" data-skin="${t}" aria-pressed="(true|false)">`), t);
  assert.match(html, /<style id="css-glass">/, 'glass sheet');
  assert.match(html, /<style id="css-terminal"[^>]*>/, 'terminal sheet');
  assert.match(html, /:root\[data-skin="terminal"\]/, 'terminal tokens are scoped to the skin attribute');
  const head = html.slice(0, html.indexOf('<body'));
  assert.match(head, /<script>[\s\S]*localStorage[\s\S]*<\/script>/, 'the one script sits in <head> so a stored choice applies before first paint');
  assert.match(html, /try \{[^}]*localStorage/, 'storage reads are guarded');
  assert.match(html, /\?theme=terminal|searchParams\.get\('theme'\)/, '?theme=terminal selects the skin, as in the app');
  assert.match(html, /<source[^>]*data-skin="terminal"/, 'a terminal screenshot source the script can enable');
});

test('W13 Homebrew: the exact install command, once, in a <code>, with a copy button and matching the README', gate, () => {
  const cmd = 'brew tap anton-g-kulikov/tap && brew install --cask backspacer';   // Homebrew 7 needs the explicit tap
  const code = html.match(/<code id="brew" data-copytext="([^"]+)">([\s\S]*?)<\/code>/);
  assert.ok(code, 'the command in <code id="brew"> with the one-line form to copy');
  assert.equal(unesc(code[1]), cmd, 'Copy puts the one-liner on the clipboard');
  assert.equal(code[2].trim(), 'brew tap anton-g-kulikov/tap\nbrew install --cask backspacer', 'shown as two terminal lines');
  assert.equal((text.match(/brew tap/g) || []).length, 1, 'one command on the page');
  assert.match(html, /<button type="button" class="copy" data-copy="brew" aria-label="Copy the Homebrew command">/);
  assert.match(html, /navigator\.clipboard\.writeText/, 'the copy button uses the clipboard API');
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  assert.ok(readme.includes(cmd), 'README documents the same command');
});

test('W14 SEO: crawl files, structured data, social card, description length, 404 page', gate, () => {
  const robots = fs.readFileSync(path.join(root, 'site/robots.txt'), 'utf8');
  assert.match(robots, /^User-agent: \*\nAllow: \/\nSitemap: https:\/\/backspacer\.dev\/sitemap\.xml\n$/);
  const sitemap = fs.readFileSync(path.join(root, 'site/sitemap.xml'), 'utf8');
  assert.match(sitemap, /<loc>https:\/\/backspacer\.dev\/<\/loc>/);
  assert.ok(fs.existsSync(path.join(root, 'site/404.html')), 'GitHub Pages serves site/404.html for unknown paths');
  const nf = fs.readFileSync(path.join(root, 'site/404.html'), 'utf8');
  assert.match(nf, /<meta name="robots" content="noindex">/);
  assert.match(nf, /href="https:\/\/backspacer\.dev\/"/, 'the 404 page links home');
  const ld = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  assert.ok(ld, 'JSON-LD present');
  const data = JSON.parse(ld[1]);
  assert.equal(data['@type'], 'SoftwareApplication');
  assert.equal(data.operatingSystem, 'macOS 13 or later');
  assert.equal(data.applicationCategory, 'UtilitiesApplication');
  assert.equal(data.offers.price, '0');
  assert.match(data.downloadUrl, /releases\/latest$/);
  assert.equal(data.softwareVersion, undefined, 'no hardcoded version: it goes stale every release');
  assert.match(html, /<p class="kicker">Free up disk space on a developer(?:'|&#39;|’)s Mac<\/p>\s*<h1>Backspacer<\/h1>/, 'a search-phrase kicker above the brand H1');
  assert.equal(data.license, 'https://polyformproject.org/licenses/noncommercial/1.0.0');
  const desc = html.match(/<meta name="description" content="([^"]*)"/)[1];
  assert.ok(desc.length >= 120 && desc.length <= 158, `description ${desc.length} chars (search snippets cut near 155)`);
  assert.match(html, /<meta name="twitter:image" content="https:\/\/backspacer\.dev\/assets\/og\.png">/);
  assert.match(html, /<meta name="twitter:title" content="[^"]+">/);
  const title = html.match(/<title>([^<]*)<\/title>/)[1];
  assert.ok(title.length <= 60, `title ${title.length} chars`);
});

test('W15 reveal hero: the System Data row unfolds into a real findings card; the app screenshot is full width below', gate, () => {
  const hero = html.match(/<section class="hero">([\s\S]*?)<\/section>/)[1];
  assert.match(hero, /<div class="reveal"/, 'the reveal sits in the hero');
  assert.match(hero, /System Data<\/b><\/span><span class="n big">74\.11 GB/, 'the macOS Storage row');
  const card = hero.match(/<div class="findings"[^>]*>([\s\S]*?)(?=<ul class="ftotals")/);
  assert.ok(card, 'a findings card');
  const rows = [...card[1].matchAll(/<div class="frow (safe|regen|decide)">[\s\S]*?<span class="fsize">(\d+(?:\.\d+)? (?:GB|MB))<\/span>/g)];
  assert.ok(rows.length >= 6, `at least six real rows (${rows.length})`);
  assert.ok(new Set(rows.map(r => r[1])).size >= 2, 'more than one bucket represented');
  assert.match(card[1], /<div class="fhead">[\s\S]*?\d+(?:\.\d+)? GB/, 'a header with the total found');
  assert.match(hero, /class="ftotals"[\s\S]*?safe to delete[\s\S]*?regenerable[\s\S]*?your call/i, 'three bucket totals');
  assert.doesNotMatch(hero, /<img|<picture/, 'no screenshot in the hero');
  assert.match(html, /@media \(min-width: 960px\) \{ \.hero-grid \{[^}]*align-items: start/, 'columns align to the top on wide screens');
  assert.match(html, /\.hero-copy \{ position: sticky; top: /, 'the copy column sticks while the reveal scrolls');
  assert.doesNotMatch(html, /class="vs"/, 'the old comparison grid is gone');
  const how = html.match(/<section id="how"[\s\S]*?<\/section>/)[0];
  assert.doesNotMatch(how, /<figure class="shot app">\s*<div class="win"/, 'real window captures carry their own chrome');
  assert.match(how, /<figure class="shot app">[\s\S]*?<img src="assets\/screenshot-light\.png" width="2274" height="1963"/, 'the real window, full width, in the buckets section');
  assert.match(how, /<figcaption>/, 'with a caption');
});

test('W16 what it is not: one AppCleaner recommendation on the site and in the README', gate, () => {
  const url = 'https://freemacsoft.net/appcleaner/';
  assert.equal((html.match(new RegExp(url.replace(/[./]/g, '\\$&'), 'g')) || []).length, 1, 'once on the page');
  assert.match(html, new RegExp(`<p class="isnot">[\\s\\S]*?<a href="${url.replace(/[./]/g, '\\$&')}">AppCleaner<\\/a>`), 'in the "what it isn\'t" line');
  assert.match(text, /isn't:?\s+an app uninstaller/i);
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  assert.ok(readme.includes(`[AppCleaner](${url})`), 'README links it too');
});

test('W17 footer links open in a new tab, safely', gate, () => {
  const foot = html.match(/<footer>([\s\S]*?)<\/footer>/)[1];
  const links = [...foot.matchAll(/<a\b[^>]*>/g)].map(m => m[0]);
  assert.ok(links.length >= 4);
  for (const l of links) if (/href="https?:/.test(l)) { assert.match(l, /target="_blank"/, l); assert.match(l, /rel="noopener"/, l); }
});

test('W18 the appcast reaches backspacer.dev: Pages deploys on a published release and ships the latest appcast', gate, () => {
  const wf = fs.readFileSync(path.join(root, '.github/workflows/pages.yml'), 'utf8');
  assert.match(wf, /release:\s*\n\s*types: \[published\]/, 'a published release triggers a deploy');
  assert.match(wf, /releases\/latest\/download\/appcast\.xml/, 'the feed comes from the latest release asset');
  assert.match(wf, /xmllint --noout site\/appcast\.xml/, 'the fetched appcast is validated before upload');
  assert.match(wf, /github\.event_name == 'release'/, 'on a release event a missing appcast fails the deploy');
  assert.match(wf, /sparkle:version|<enclosure/, 'the check looks for Sparkle content, not just XML');
  const ignore = fs.readFileSync(path.join(root, '.gitignore'), 'utf8');
  assert.match(ignore, /^site\/appcast\.xml$/m, 'the fetched feed is never committed');
});

test('W19 the meta line says the app updates itself; no upgrade footnote', gate, () => {
  const hero = html.match(/<section class="hero">([\s\S]*?)<\/section>/)[1];
  assert.match(hero, /<li>Updates itself<\/li>/);
  assert.doesNotMatch(text, /Updating from 0\.9/);
});

test('W9 the Pages workflow publishes site/ on pushes to main', gate, () => {
  const wf = fs.readFileSync(path.join(root, '.github/workflows/pages.yml'), 'utf8');
  assert.match(wf, /branches: \[main\]/);
  assert.match(wf, /paths:\s*\n\s*- 'site\/\*\*'/);
  assert.match(wf, /permissions:\s*\n\s*contents: read\s*\n\s*pages: write\s*\n\s*id-token: write/);
  assert.match(wf, /actions\/upload-pages-artifact@[0-9a-f]{40}/, 'actions pinned by SHA');
  assert.match(wf, /actions\/deploy-pages@[0-9a-f]{40}/, 'actions pinned by SHA');
  assert.match(wf, /path: site/);
  assert.match(wf, /node --test 'Tests\/web\/site\.test\.js'/, 'the site tests gate the deploy');
  assert.match(wf, /SITE_REQUIRED: 1/, 'in the workflow a missing page fails instead of skipping');
});
