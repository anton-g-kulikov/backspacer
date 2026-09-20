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

## Steps
1. `swift test` is green; `git status` is clean; CHANGELOG has the version's entry.
2. Tag: `git tag -a vX.Y.Z -m "Backspacer X.Y.Z"` — `build-app.sh` reads the
   version from `git describe --tags`. Tag the *final* commit: an amend after
   tagging makes the version read `X.Y.Z-1-g…`; re-tag with `git tag -f -a`.
3. Build: `IDENTITY="Developer ID Application: ANTON KULIKOV (R9BBCR3NF6)" scripts/build-app.sh`
   — expect `arch: x86_64 arm64` and `signature OK`.
4. Smoke-test `open build/Backspacer.app`: scans, theme switch, one delete with confirm/cancel.
5. Notarize: `scripts/notarize.sh` — expect `status: Accepted` twice (app, DMG)
   and "notarized and stapled". On rejection the script prints the notary log.
6. Verify from a user's point of view:
   `spctl --assess --type open --context context:primary-signature -v build/Backspacer-X.Y.Z.dmg`
   and, with the DMG mounted, `spctl --assess --type execute -v /Volumes/Backspacer/Backspacer.app` → `accepted`.
7. Push: `git push origin main --tags`.
8. Release: `gh release create vX.Y.Z build/Backspacer-X.Y.Z.dmg --title "Backspacer X.Y.Z" --notes-file <notes>`.
9. Remove the previous version's `.dmg`/`.zip` from `build/`.

## Rollback
- A bad DMG: delete the GitHub release asset, fix, bump the build number
  (`BUILD_NUM` is a timestamp, so a rebuild is enough), re-run from step 3.
- Notarization can't be revoked by us; a rejected build never staples, so it
  never ships.

## After
- Check the tag's CI run went green (`gh run list --branch vX.Y.Z`); it packages
  the app ad-hoc as a guard. It failing does not affect the shipped DMG, which
  was built and notarized locally, but fix the guard before the next release.
- Move the task's entry in `_meta/project-task-list.md` to Done.
- Note anything that surprised you in this checklist.
