// Rewrites the sha256 hashes in site/index.html's Content-Security-Policy to match its
// inline <style> and <script> blocks. Run after editing either; W11 fails when they drift.
//   node scripts/site-csp.mjs          # rewrite
//   node scripts/site-csp.mjs --check  # exit 1 when out of date
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const path = new URL('../site/index.html', import.meta.url);
const html = readFileSync(path, 'utf8');
const sha = s => 'sha256-' + createHash('sha256').update(s).digest('base64');
const blocks = tag => [...html.matchAll(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, 'g'))].map(m => m[1]);
if (!blocks('style').length || !blocks('script').length) throw new Error('no <style> or <script>');
const want = { 'style-src': blocks('style').map(sha).map(h => `'${h}'`).join(' '), 'script-src': blocks('script').map(sha).map(h => `'${h}'`).join(' ') };
let out = html;
for (const [dir, hashes] of Object.entries(want)) out = out.replace(new RegExp(`${dir} '[^;]*'`), `${dir} ${hashes}`);
if (process.argv.includes('--check')) { if (out !== html) { console.error('CSP hashes are stale — run node scripts/site-csp.mjs'); process.exit(1); } console.log('CSP hashes current'); }
else { writeFileSync(path, out); console.log('CSP', want); }
