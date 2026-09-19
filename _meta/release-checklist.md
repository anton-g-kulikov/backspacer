# Release Checklist

Repeated, error-prone task. Update this when a step turns out to be missing.

## Prerequisites (once per machine)
- Developer ID Application certificate in the login keychain
  (`security find-identity -v -p codesigning` lists it).
- `notarytool` profile named `Reclaimer` stored with the Apple ID that owns team
  R9BBCR3NF6. Check: `xcrun notarytool history --keychain-profile Reclaimer`.
  A `401` means the profile's Apple ID or app-specific password is stale —
  re-run `store-credentials` (never paste the password into a script).

## Steps
1. `swift test` is green; `git status` is clean; CHANGELOG has the version's entry.
2. Tag: `git tag -a vX.Y.Z -m "Reclaimer X.Y.Z"` — `build-app.sh` reads the
   version from `git describe --tags`. Tag the *final* commit: an amend after
   tagging makes the version read `X.Y.Z-1-g…`; re-tag with `git tag -f -a`.
3. Build: `IDENTITY="Developer ID Application: ANTON KULIKOV (R9BBCR3NF6)" scripts/build-app.sh`
   — expect `arch: x86_64 arm64` and `signature OK`.
4. Smoke-test `open build/Reclaimer.app`: scans, theme switch, one delete with confirm/cancel.
5. Notarize: `scripts/notarize.sh` — expect `status: Accepted` twice (app, DMG)
   and "notarized and stapled". On rejection the script prints the notary log.
6. Verify from a user's point of view:
   `spctl --assess --type open --context context:primary-signature -v build/Reclaimer-X.Y.Z.dmg`
   and, with the DMG mounted, `spctl --assess --type execute -v /Volumes/Reclaimer/Reclaimer.app` → `accepted`.
7. Push: `git push origin main --tags`.
8. Release: `gh release create vX.Y.Z build/Reclaimer-X.Y.Z.dmg --title "Reclaimer X.Y.Z" --notes-file <notes>`.
9. Remove the previous version's `.dmg`/`.zip` from `build/`.

## Rollback
- A bad DMG: delete the GitHub release asset, fix, bump the build number
  (`BUILD_NUM` is a timestamp, so a rebuild is enough), re-run from step 3.
- Notarization can't be revoked by us; a rejected build never staples, so it
  never ships.

## After
- Move the task's entry in `_meta/project-task-list.md` to Done.
- Note anything that surprised you in this checklist.
