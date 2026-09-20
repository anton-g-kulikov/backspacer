# Security

Backspacer deletes folders. If you find a way it could remove something it
shouldn't — a catalog path that resolves outside the allowed roots, a way for
the page to name a path, a gate that lets a user-data folder through — please
email anton.g.kulikov@gmail.com rather than opening a public issue. You'll get
a reply within a few days and credit in the changelog if you want it.

## Verifying a download

Every release is built by the tag-triggered workflow (`.github/workflows/release.yml`),
signed with the maintainer's Developer ID and notarized by Apple. To check a DMG:

- Gatekeeper: `spctl --assess --type open --context context:primary-signature -v Backspacer-X.Y.Z.dmg` → `accepted`.
- Hash: `shasum -a 256 Backspacer-X.Y.Z.dmg` matches the SHA-256 in the release notes
  (and the `sha256` in the Homebrew cask at github.com/anton-g-kulikov/homebrew-tap).
- Provenance: `gh attestation verify Backspacer-X.Y.Z.dmg --owner anton-g-kulikov`
  proves the file was produced by that workflow from the tagged commit.

The app makes one network request: after the first scan of a session it asks GitHub's
releases API whether a newer version exists (at most once a day, off in About). It
sends nothing about you or your disk.

What's already in place: every disk operation takes a catalog id, not a path;
`Bridge.isSafeToDelete` refuses home, `~/Library`, top-level user folders and
anything outside `~/`, `/Library/Developer/` and the staged-update folder;
per-item deletes are selectors validated against a fresh resolve; the tests
run the gate over every path in the shipped catalog (`SafetyGateTests` S7).
