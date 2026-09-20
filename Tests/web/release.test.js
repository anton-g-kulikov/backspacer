// The tag-triggered release workflow: shape checks over .github/workflows/release.yml and the
// notarize script it drives. Run: node --test 'Tests/web/*.test.js'
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../..');
const wf = fs.readFileSync(path.join(root, '.github/workflows/release.yml'), 'utf8');
const notarize = fs.readFileSync(path.join(root, 'scripts/notarize.sh'), 'utf8');

test('Y1 fires on version tags only', () => {
  assert.match(wf, /^on:\n  push:\n    tags: \['v\*'\]\n/m);
  assert.doesNotMatch(wf, /branches:/);
  assert.doesNotMatch(wf, /pull_request/);
});

test('Y2 permissions: write releases, mint an OIDC token and store the attestation, nothing else', () => {
  const block = wf.match(/^permissions:\n((?:  .*\n)+)/m)[1];
  assert.deepEqual(block.trim().split('\n').map((l) => l.trim()).sort(), ['attestations: write', 'contents: write', 'id-token: write']);
});

test('Y3 every action is pinned to a commit SHA', () => {
  const uses = [...wf.matchAll(/uses: ([^\s@]+)@(\S+)/g)];
  assert.ok(uses.length >= 2);
  for (const [, action, ref] of uses) assert.match(ref, /^[0-9a-f]{40}$/, `${action} is pinned by SHA`);
});

test('Y4 tests run before anything is signed; steps fail on any error in a pipe', () => {
  assert.match(wf, /shell: bash/);
  const order = ['swift test', 'node --test', 'security create-keychain', 'scripts/build-app.sh', 'scripts/notarize.sh', 'gh release create'];
  const idx = order.map((s) => wf.indexOf(s));
  assert.ok(idx.every((i) => i >= 0), `all steps present: ${JSON.stringify(Object.fromEntries(order.map((s, i) => [s, idx[i]])))}`);
  assert.deepEqual([...idx].sort((a, b) => a - b), idx, 'in that order');
});

test('Y5 the certificate lives in a temporary keychain that is deleted whatever happens', () => {
  assert.match(wf, /security create-keychain -p "\$KEYCHAIN_PASSWORD" "\$KEYCHAIN"/);
  assert.match(wf, /security import .* -P "\$\{\{ secrets\.MACOS_CERT_PASSWORD \}\}"/);
  assert.match(wf, /if: always\(\)\n\s+run: security delete-keychain "\$RUNNER_TEMP\/release\.keychain-db"/, 'deleted in an always() step');
  assert.doesNotMatch(wf, /\$\{\{ runner\./, 'the runner context is not available in job-level env — a parse error, not a runtime one');
  assert.doesNotMatch(wf, /login\.keychain/);
});

test('Y6 notarization uses the secrets, never a keychain profile; the script accepts them from the environment', () => {
  assert.match(wf, /NOTARY_APPLE_ID: \$\{\{ secrets\.APPLE_ID \}\}/);
  assert.match(wf, /NOTARY_PASSWORD: \$\{\{ secrets\.APPLE_APP_PASSWORD \}\}/);
  assert.match(wf, /NOTARY_TEAM_ID: \$\{\{ secrets\.APPLE_TEAM_ID \}\}/);
  assert.doesNotMatch(wf, /--keychain-profile/);
  assert.match(notarize, /if \[ -n "\$\{NOTARY_APPLE_ID:-\}" \]; then\n\s+AUTH=\(--apple-id "\$NOTARY_APPLE_ID" --password "\$NOTARY_PASSWORD" --team-id "\$NOTARY_TEAM_ID"\)/);
  assert.match(notarize, /AUTH=\(--keychain-profile "\$PROFILE"\)/, 'the local path still uses the profile');
  assert.doesNotMatch(notarize, /echo .*NOTARY_PASSWORD/, 'the password is never printed');
});

test('Y7 the release carries the DMG, its SHA-256 in the notes, and a build-provenance attestation', () => {
  assert.match(wf, /SHA="\$\(shasum -a 256 "\$DMG" \| cut -d' ' -f1\)"/, 'the DMG is hashed');
  assert.match(wf, /SHA-256 .*\$SHA/, "and the hash goes into the notes");
  assert.match(wf, /DMG="build\/Backspacer-\$V\.dmg"[\s\S]*gh release create "\$\{GITHUB_REF_NAME\}" "\$DMG"/, 'the DMG is the release asset');
  assert.match(wf, /uses: actions\/attest-build-provenance@[0-9a-f]{40}/);
  assert.match(wf, /subject-path: .*\.dmg/);
  assert.match(wf, /spctl --assess --type open/, 'Gatekeeper is asked before publishing');
});

test('Y8 the release run deploys the site itself: GITHUB_TOKEN events never trigger other workflows', () => {
  // `gh release create` inside release.yml raises `release: published`, but events created with the
  // workflow token do not start workflows — so pages.yml is called as a reusable workflow instead.
  assert.match(wf, /^  site:\n    needs: release\n(?:.*\n)*?    uses: \.\/\.github\/workflows\/pages\.yml\n    with:\n      required: true\n/m);
  const pages = fs.readFileSync(path.join(root, '.github/workflows/pages.yml'), 'utf8');
  assert.match(pages, /^  workflow_call:\n    inputs:\n      required:\n        type: boolean\n/m, 'pages.yml accepts the call with a required flag');
  assert.match(pages, /REQUIRED: \$\{\{ github\.event_name == 'release' \|\| inputs\.required == true \}\}/);
  const site = wf.slice(wf.indexOf('  site:'));
  assert.match(site, /permissions:\n      contents: read\n      pages: write\n      id-token: write/, 'the caller grants what Pages needs');
});

test('Y9 CI keeps a deep signature check on the packaged bundle, so a Sparkle bump that breaks the nested signing fails on push', () => {
  const ci = fs.readFileSync(path.join(root, '.github/workflows/ci.yml'), 'utf8');
  const pkg = ci.slice(ci.indexOf('Package and verify the app bundle'));
  assert.match(pkg, /UNIVERSAL=1 scripts\/build-app\.sh/, 'the real build script, which signs Sparkle inside out');
  assert.match(pkg, /codesign --verify --deep --strict build\/Backspacer\.app/, 'deep-strict verification covers the XPC services and the framework');
  assert.doesNotMatch(ci, /if: startsWith\(github\.ref, 'refs\/tags\/v'\)/, 'on every push, not only tags');
});
