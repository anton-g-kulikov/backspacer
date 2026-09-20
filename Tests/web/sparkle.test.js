// In-app updates with Sparkle 2 (ADR-21): shape checks over the package manifest, the build
// script and the release workflow. Run: node --test 'Tests/web/*.test.js'
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

test('Z1 Sparkle is a SwiftPM dependency pinned by revision, and resolved to that revision', () => {
  const pkg = read('Package.swift');
  const m = pkg.match(/\.package\(url: "https:\/\/github\.com\/sparkle-project\/Sparkle(?:\.git)?", revision: "([0-9a-f]{40})"\)/);
  assert.ok(m, 'pinned by a 40-hex revision, not a version range');
  assert.match(pkg, /\.product\(name: "Sparkle", package: "Sparkle"\)/);
  const resolved = JSON.parse(read('Package.resolved'));
  const pin = resolved.pins.find((p) => p.identity === 'sparkle');
  assert.equal(pin.state.revision, m[1], 'Package.resolved agrees with the manifest');
});

test('Z2 build-app.sh embeds Sparkle.framework and signs inside out — XPC services, framework, app', () => {
  const sh = read('scripts/build-app.sh');
  assert.match(sh, /Contents\/Frameworks\/Sparkle\.framework/);
  const xpc = sh.indexOf('XPCServices/*.xpc');
  const fw = sh.indexOf('sign_nested "$APP/Contents/Frameworks/Sparkle.framework"');
  const app = sh.indexOf('--sign "$IDENTITY" "$APP"');
  assert.ok(xpc > 0 && fw > xpc && app > fw, `order: xpc ${xpc} < framework ${fw} < app ${app}`);
  assert.doesNotMatch(sh, /codesign --force[^\n]*--deep/, 'no --deep signing');
  assert.match(sh, /codesign --verify --deep --strict "\$APP"/, 'but a deep verification');
  assert.doesNotMatch(sh, /nested code found/, 'the guard is replaced by the real signing step');
});

test('Z3 Info.plist carries the feed, the public key and the update policy; a dev build has no feed', () => {
  const sh = read('scripts/build-app.sh');
  assert.match(sh, /SUEnableAutomaticChecks<\/key><true\/>/);
  assert.match(sh, /SUAutomaticallyUpdate<\/key><false\/>/, 'download, but ask before installing');
  assert.match(sh, /SUScheduledCheckInterval<\/key><integer>86400<\/integer>/);
  assert.match(sh, /SUFeedURL<\/key><string>https:\/\/backspacer\.dev\/appcast\.xml<\/string>/);
  assert.match(sh, /SUPublicEDKey<\/key><string>\$SPARKLE_PUBLIC_KEY<\/string>/);
  assert.match(sh, /if \[ -n "\$\{IDENTITY:-\}" \]; then\n\s+SPARKLE_KEYS=/, 'feed and key only in distribution builds');
});

const { execFileSync } = require('node:child_process');

test('Z4 make-appcast.sh writes one valid item: versions, EdDSA signature, length, DMG URL, min system, inline notes', () => {
  const notes = path.join(require('node:os').tmpdir(), 'notes-z4.md');
  fs.writeFileSync(notes, '- Fixed: links in About opened **inside** the window.\n- New: `brew install --cask backspacer`.\n');
  const xml = execFileSync('bash', ['scripts/make-appcast.sh', '0.9.4', '202609201100', '916911', 'SIGBASE64==',
    'https://github.com/anton-g-kulikov/backspacer/releases/download/v0.9.4/Backspacer-0.9.4.dmg',
    'https://github.com/anton-g-kulikov/backspacer/releases/tag/v0.9.4', notes], { cwd: root, encoding: 'utf8' });
  assert.match(xml, /^<\?xml version="1\.0" encoding="utf-8"\?>/);
  assert.match(xml, /xmlns:sparkle="http:\/\/www\.andymatuschak\.org\/xml-namespaces\/sparkle"/);
  assert.match(xml, /<sparkle:version>202609201100<\/sparkle:version>/, 'sparkle:version is CFBundleVersion');
  assert.match(xml, /<sparkle:shortVersionString>0\.9\.4<\/sparkle:shortVersionString>/);
  assert.match(xml, /<sparkle:minimumSystemVersion>13\.0<\/sparkle:minimumSystemVersion>/);
  assert.match(xml, /<sparkle:fullReleaseNotesLink>https:\/\/github\.com\/anton-g-kulikov\/backspacer\/releases\/tag\/v0\.9\.4<\/sparkle:fullReleaseNotesLink>/, 'the GitHub page is the full-notes link, not the pane');
  assert.match(xml, /<description><!\[CDATA\[[\s\S]*<ul>\s*<li>Fixed: links in About opened <b>inside<\/b> the window\.<\/li>\s*<li>New: <code>brew install --cask backspacer<\/code>\.<\/li>\s*<\/ul>[\s\S]*\]\]><\/description>/, 'the changelog section, as clean HTML in the pane');
  assert.doesNotMatch(xml, /<sparkle:releaseNotesLink>/);
  assert.match(xml, /<enclosure url="https:\/\/github\.com\/anton-g-kulikov\/backspacer\/releases\/download\/v0\.9\.4\/Backspacer-0\.9\.4\.dmg" length="916911" type="application\/octet-stream" sparkle:edSignature="SIGBASE64=="\/>/);
  assert.equal((xml.match(/<item>/g) || []).length, 1, 'the latest release only');
  execFileSync('xmllint', ['--noout', '-'], { input: xml });
});

test('Z5 release.yml signs the DMG with the secret key and ships the appcast as a release asset', () => {
  const wf = read('.github/workflows/release.yml');
  assert.match(wf, /SPARKLE_ED_KEY: \$\{\{ secrets\.SPARKLE_ED_KEY \}\}/);
  assert.match(wf, /sign_update --ed-key-file "\$KEYFILE" "\$DMG"/, 'the key goes through a temp file, never the command line');
  assert.match(wf, /rm -P "\$KEYFILE"/);
  assert.match(wf, /scripts\/make-appcast\.sh/);
  assert.match(wf, /gh release create "\$\{GITHUB_REF_NAME\}" "\$DMG" "\$RUNNER_TEMP\/appcast\.xml"/, 'the appcast rides with the DMG');
  const sign = wf.indexOf('sign_update'); const notarize = wf.indexOf('scripts/notarize.sh'); const publish = wf.indexOf('gh release create');
  assert.ok(notarize < sign && sign < publish, 'signed after notarization (the stapled DMG is what ships), before publishing');
});
