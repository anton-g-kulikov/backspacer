# Release Checklist

Repeated, error-prone task. Update this when a step turns out to be missing.

## Prerequisites (once per machine)
Requires an Apple Developer Program membership.
1. Developer ID Application certificate in the login keychain: Xcode → Settings →
   Accounts → *Manage Certificates* → **+** → *Developer ID Application*.
   Check: `security find-identity -v -p codesigning` lists
   `Developer ID Application: ANTON KULIKOV (R9BBCR3NF6)`.
2. An app-specific password from account.apple.com → Sign-In and Security, for
   the Apple ID that owns team R9BBCR3NF6 (anton.g.kulikov@gmail.com).
3. `xcrun notarytool store-credentials Backspacer --apple-id anton.g.kulikov@gmail.com --team-id R9BBCR3NF6`
   (prompts for the password; never put it in a script).
   Check: `xcrun notarytool history --keychain-profile Backspacer`. A `401` means
   the profile's Apple ID or password is stale — re-run store-credentials.

Signing is not `--deep`: the app has a single Mach-O. If a framework, XPC service
or helper app is ever added, sign it explicitly (its own `codesign` line, its own
entitlements) *before* the app; the build script refuses to sign a bundle with
unsigned nested code.

Build knobs (`scripts/build-app.sh`): `IDENTITY` selects Developer ID signing
and a universal binary (`UNIVERSAL=0/1` overrides); the version comes from
`git describe --tags` (`VERSION=…` overrides); the icon is `assets/AppIcon.icns`.
On a rejected submission `scripts/notarize.sh` prints the notary log, which
names every offending file.

## Steps (tag-triggered — the normal path)
1. `swift test` and the node suites are green; `git status` is clean; CHANGELOG has
   a `## X.Y.Z — date` section (the workflow refuses a tag without one).
2. Smoke-test a local build once: `scripts/build-app.sh && open -n build/Backspacer.app`
   — scans, theme switch, one delete with confirm/cancel.
3. Tag the *final* commit and push it:
   `git tag -a vX.Y.Z -m "Backspacer X.Y.Z" && git push origin main --tags`.
   An amend after tagging makes the version read `X.Y.Z-1-g…`; re-tag with `git tag -f -a`.
4. Watch `.github/workflows/release.yml` (`gh run list --workflow Release`): it runs the
   tests, builds the universal app signed with the certificate from the secrets in a
   temporary keychain, notarizes app and DMG, staples, asks Gatekeeper, publishes the
   GitHub release with the changelog section and the DMG's SHA-256, and attaches a
   build-provenance attestation. A rejected notarization prints Apple's log in the run.
5. Check the release page: DMG present, notes right, `gh attestation verify
   Backspacer-X.Y.Z.dmg --owner anton-g-kulikov` passes.
6. Homebrew: the tap (github.com/anton-g-kulikov/homebrew-tap) bumps its cask to the
   latest release by itself within six hours, after checking the DMG's SHA-256 against
   the release notes and auditing the cask. To bump it now:
   `gh workflow run bump.yml -R anton-g-kulikov/homebrew-tap`, then
   `brew update && brew info --cask anton-g-kulikov/tap/backspacer` shows X.Y.Z.

### Secrets the workflow needs (once, Settings → Secrets and variables → Actions)
| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | the Developer ID Application certificate **with its private key**, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | the password chosen at export |
| `APPLE_ID` | `anton.g.kulikov@gmail.com` |
| `APPLE_APP_PASSWORD` | an app-specific password (account.apple.com → Sign-In and Security); the one behind the local `Backspacer` profile works too |
| `APPLE_TEAM_ID` | `R9BBCR3NF6` |
Rotate `APPLE_APP_PASSWORD` by revoking it at account.apple.com and storing a new one;
the certificate expires May 2031. Never paste any of these into a script or a commit.

## Steps (manual fallback — when Actions is down or the secrets aren't set)
1. Tag as above, but don't push yet.
2. Build: `IDENTITY="Developer ID Application: ANTON KULIKOV (R9BBCR3NF6)" scripts/build-app.sh`
   — expect `arch: x86_64 arm64` and `signature OK`.
3. Notarize: `scripts/notarize.sh` (uses the `Backspacer` keychain profile) — expect
   `status: Accepted` twice (app, DMG) and "notarized and stapled".
4. Verify: `spctl --assess --type open --context context:primary-signature -v build/Backspacer-X.Y.Z.dmg`
   and, with the DMG mounted, `spctl --assess --type execute -v /Volumes/Backspacer/Backspacer.app` → `accepted`.
5. Push: `git push origin main --tags`. The Release workflow will run and fail at the
   secrets if they aren't set — that's expected on this path.
6. Release: `gh release create vX.Y.Z build/Backspacer-X.Y.Z.dmg --title "Backspacer X.Y.Z" --notes-file <notes>`
   (if the workflow already created it, upload with `gh release upload` instead).
7. Remove the previous version's `.dmg`/`.zip` from `build/`.

## Rollback
- A run that failed after publishing (or a bad DMG): delete the GitHub release and the tag (`gh release delete vX.Y.Z --yes`,
  `git push origin :refs/tags/vX.Y.Z`), fix, re-tag the fixed commit and push again.
- Notarization can't be revoked by us; a rejected build never staples, so it
  never ships.

## After
- Check the tag's CI run went green (`gh run list --branch vX.Y.Z`); it packages
  the app ad-hoc as a guard. It failing does not affect the shipped DMG, which
  was built and notarized locally, but fix the guard before the next release.
- Move the task's entry in `_meta/project-task-list.md` to Done.
- Note anything that surprised you in this checklist.
