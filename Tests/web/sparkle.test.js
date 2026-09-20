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
