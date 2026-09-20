// Static checks over the promo site (site/index.html, published by GitHub Pages).
// Run: node --test 'Tests/web/*.test.js'
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '../..');
const sitePath = path.join(root, 'site/index.html');
const html = fs.existsSync(sitePath) ? fs.readFileSync(sitePath, 'utf8') : '';
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'catalog.json'), 'utf8'));
const text = html.replace(/<style[\s\S]*?<\/style>|<script[\s\S]*?<\/script>/g, '').replace(/<[^>]+>/g, ' ');
const unesc = s => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");

test('W1 the page exists with the head every crawler and share card needs', () => {
  assert.ok(html.length > 0, 'site/index.html exists');
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<meta charset="utf-8">/);
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
  assert.match(html, /<title>Reclaimery[^<]*<\/title>/);
  assert.match(html, /<meta name="description" content="[^"]{60,}">/);
  for (const p of ['og:title', 'og:description', 'og:image', 'og:url', 'twitter:card']) {
    assert.match(html, new RegExp(`<meta (?:property|name)="${p}" content="[^"]+">`), p);
  }
  assert.match(html, /<link rel="icon"/);
  assert.match(html, /<meta http-equiv="Content-Security-Policy" content="default-src 'none';/);
});

test('W2 every local asset the page references exists under site/', () => {
  const refs = [...html.matchAll(/(?:src|href|srcset|content)="([^"]+)"/g)].map(m => m[1])
    .flatMap(v => v.split(',').map(s => s.trim().split(' ')[0]))
    .filter(v => v && !/^(https?:|mailto:|#|data:)/.test(v));
  assert.ok(refs.length >= 4, 'the page references local assets (icon, screenshots)');
  for (const r of refs) assert.ok(fs.existsSync(path.join(root, 'site', r)), `missing site/${r}`);
});

test('W3 download and source links go to the GitHub repo', () => {
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/reclaimer\/releases\/latest"/);
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/reclaimer"/);
  assert.match(html, /api\.github\.com\/repos\/anton-g-kulikov\/reclaimer\/releases\/latest/, 'the version badge is fetched live');
});

test('W4 the bucket names and blurbs are the catalog\'s, verbatim', () => {
  for (const b of Object.values(catalog.buckets)) {
    assert.ok(unesc(text).includes(b.title), `bucket title "${b.title}"`);
    assert.ok(unesc(text).includes(b.blurb), `bucket blurb "${b.blurb}"`);
  }
});

test('W5 every catalog group the page names is a real group, and the entry count is current', () => {
  const groups = new Set(catalog.entries.map(e => e.group));
  const named = [...html.matchAll(/data-group="([^"]+)"/g)].map(m => unesc(m[1]));
  assert.ok(named.length >= 8, 'the "what it finds" section lists catalog groups');
  for (const g of named) assert.ok(groups.has(g), `"${g}" is not a catalog group`);
  assert.match(text, new RegExp(`\\b${catalog.entries.length} entries\\b`), 'entry count matches catalog.json');
});

test('W6 license wording follows ADR-14: noncommercial, never "open source"', () => {
  assert.doesNotMatch(text, /open[- ]source/i);
  assert.match(text, /free for noncommercial use/i);
  assert.match(html, /href="https:\/\/polyformproject\.org\/licenses\/noncommercial\/1\.0\.0"/);
  assert.match(html, /href="https:\/\/github\.com\/anton-g-kulikov\/reclaimer\/blob\/main\/LICENSE"/);
});

test('W7 accessibility basics: landmarks, one h1, skip link, alt text, named controls, motion and contrast', () => {
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

test('W8 the wordmark is Reclaimer(y) and the page explains the name once', () => {
  assert.match(html, /<h1[^>]*>\s*Reclaimer<span[^>]*aria-hidden="true"[^>]*>\(y\)<\/span>/);
  assert.match(html, /<h1[^>]*aria-label="Reclaimery"/);
  assert.match(text, /\(y\/n\)/);
});

test('W9 the Pages workflow publishes site/ on pushes to main', () => {
  const wf = fs.readFileSync(path.join(root, '.github/workflows/pages.yml'), 'utf8');
  assert.match(wf, /branches: \[main\]/);
  assert.match(wf, /paths:\s*\n\s*- 'site\/\*\*'/);
  assert.match(wf, /permissions:\s*\n\s*contents: read\s*\n\s*pages: write\s*\n\s*id-token: write/);
  assert.match(wf, /actions\/upload-pages-artifact@[0-9a-f]{40}/, 'actions pinned by SHA');
  assert.match(wf, /actions\/deploy-pages@[0-9a-f]{40}/, 'actions pinned by SHA');
  assert.match(wf, /path: site/);
  assert.match(wf, /node --test 'Tests\/web\/site\.test\.js'/, 'the site tests gate the deploy');
});
