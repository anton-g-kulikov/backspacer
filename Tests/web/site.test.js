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
    .filter(v => v && !/^(https?:|mailto:|#|data:)/.test(v));
  assert.ok(refs.length >= 4, 'the page references local assets (icon, screenshots)');
  for (const r of refs) assert.ok(fs.existsSync(path.join(root, 'site', r)), `missing site/${r}`);
  const og = html.match(/property="og:image" content="https:\/\/backspacer\.dev\/([^"]+)"/);
  assert.ok(og && fs.existsSync(path.join(root, 'site', og[1])), 'og:image is a site file on the canonical host');
});

test('W3 download and source links go to the GitHub repo', gate, () => {
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/backspacer\/releases\/latest"/);
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/backspacer"/);
  assert.match(html, /api\.github\.com\/repos\/anton-g-kulikov\/backspacer\/releases\/latest/, 'the version badge is fetched live');
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
});

test('W8 the wordmark is Backspacer (y) and the page explains the wink once', gate, () => {
  assert.match(html, /<h1[^>]*aria-label="Backspacer"[^>]*>\s*Backspacer\s*<span[^>]*aria-hidden="true"[^>]*>\(y\)<\/span>/);
  assert.match(text, /\(y\/n\)/);
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
  const block = tag => html.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`))[1];
  const csp = html.match(/Content-Security-Policy" content="([^"]+)"/)[1];
  assert.ok(csp.includes(`style-src '${sha(block('style'))}'`), 'style hash (run node scripts/site-csp.mjs)');
  assert.ok(csp.includes(`script-src '${sha(block('script'))}'`), 'script hash (run node scripts/site-csp.mjs)');
  assert.equal((html.match(/<style/g) || []).length, 1); assert.equal((html.match(/<script/g) || []).length, 1);
  assert.doesNotMatch(html, /\bon[a-z]+="/, 'no inline event handlers (CSP would block them)');
  assert.doesNotMatch(html, /\sstyle="/, 'no style attributes (a hashed style-src blocks them)');
  assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
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
