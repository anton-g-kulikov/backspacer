#!/bin/bash
# Signs, notarizes and staples build/Backspacer.app, then wraps it in a DMG.
#
# One-time setup (Apple Developer Program membership required):
#   1. Xcode → Settings → Accounts → Manage Certificates → "+" → Developer ID Application
#   2. App-specific password at https://appleid.apple.com → Sign-In and Security
#   3. xcrun notarytool store-credentials backspacer \
#        --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# Then:
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
#   scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Backspacer.app"
PROFILE="${PROFILE:-Backspacer}"          # notarytool keychain profile name
[ -d "$APP" ] || { echo "run scripts/build-app.sh first"; exit 1; }

if codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
  echo "✗ $APP is ad-hoc signed. Rebuild with IDENTITY set to your Developer ID."; exit 1
fi

# Submits a file and waits. notarytool's exit code alone isn't a reliable verdict,
# so grep the status and pull the log (lists every rejected file) when it isn't Accepted.
notarize() {
  local out
  out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1) || true
  echo "$out"
  if ! grep -q "status: Accepted" <<<"$out"; then
    local sub_id; sub_id=$(sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' <<<"$out" | head -1)
    echo "✗ notarization of $1 was not accepted"
    [ -n "$sub_id" ] && xcrun notarytool log "$sub_id" --keychain-profile "$PROFILE"
    exit 1
  fi
}

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
ZIP="build/Backspacer-$VERSION.zip"
DMG="build/Backspacer-$VERSION.dmg"

if xcrun stapler validate "$APP" >/dev/null 2>&1; then
  echo "▸ $APP already notarized and stapled — skipping to DMG"
else
  echo "▸ zipping for submission"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"

  echo "▸ submitting to Apple notary service (this waits; usually 1–5 min)"
  notarize "$ZIP"

  echo "▸ stapling ticket"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi
spctl --assess --type execute -vv "$APP" 2>&1 | tail -2

echo "▸ building DMG"
rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Backspacer" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)$/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ couldn't read the Developer ID identity from $APP"; exit 1; }
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "✓ $DMG is notarized and stapled — safe to share."
