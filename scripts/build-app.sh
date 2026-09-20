#!/bin/bash
# Builds Backspacer.app into build/ from the SwiftPM package.
#
#   scripts/build-app.sh            → ad-hoc signed (runs on this Mac only)
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
#                                   → signed for distribution; follow with scripts/notarize.sh
#   UNIVERSAL=1 …                   → arm64 + x86_64 binary (default when IDENTITY is set)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Backspacer"
BUNDLE_ID="${BUNDLE_ID:-com.antonkulikov.backspacer}"
VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.1.0)}"
BUILD_NUM="${BUILD_NUM:-$(date +%Y%m%d%H%M)}"
MIN_OS="13.0"
APP="build/$APP_NAME.app"
# Distribution builds are universal so Intel Macs can run them; dev builds stay native for speed.
UNIVERSAL="${UNIVERSAL:-$([ -n "${IDENTITY:-}" ] && echo 1 || echo 0)}"

SWIFT_FLAGS=(-c release)
[ "$UNIVERSAL" = 1 ] && SWIFT_FLAGS+=(--arch arm64 --arch x86_64)

echo "▸ swift build (${SWIFT_FLAGS[*]})"
swift build "${SWIFT_FLAGS[@]}" 2>&1 | grep -v 'x86_64 architecture is deprecated' | tail -3
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/$APP_NAME"   # output dir differs per toolchain
[ -x "$BIN" ] || { echo "binary not found at $BIN"; exit 1; }

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
# Sparkle (ADR-21): the universal framework from the pinned SwiftPM artifact, next to the binary,
# and an rpath so the binary finds it inside the bundle.
SPARKLE_SRC="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/../../artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_SRC" ] || SPARKLE_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_SRC" ] || { echo "Sparkle.framework not found — run swift package resolve"; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME"
cp -R web "$APP/Contents/Resources/web"
cp catalog.json "$APP/Contents/Resources/catalog.json"
[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod -R u+rwX,go+rX "$APP"   # sources may be 0600; other accounts must be able to read the bundle

# Distribution builds get the feed and the EdDSA public key (SPARKLE_PUBLIC_KEY, printed once by
# Sparkle's generate_keys); a dev build has no feed, so the updater stays off and needs no key.
if [ -n "${IDENTITY:-}" ]; then
  SPARKLE_KEYS="  <key>SUFeedURL</key><string>https://backspacer.dev/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>"
  [ -n "${SPARKLE_PUBLIC_KEY:-}" ] || { echo "SPARKLE_PUBLIC_KEY is not set (the public half from generate_keys)"; exit 1; }
else
  SPARKLE_KEYS=""
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUM</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Anton Kulikov</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
$SPARKLE_KEYS
</dict></plist>
PLIST
echo "APPL????" > "$APP/Contents/PkgInfo"

echo "▸ codesign"
# No --deep: nested code is signed explicitly, inside out, each piece keeping its own
# entitlements (Sparkle's Downloader.xpc is sandboxed). Order: the framework's XPC services and
# helpers, then the framework, then the app — a piece signed after its container would break
# the container's seal.
SIGN_ID="${IDENTITY:--}"
sign_nested() {
  if [ -n "${IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$1"
  else
    codesign --force --preserve-metadata=entitlements --sign - "$1"
  fi
}
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for x in "$SPK"/XPCServices/*.xpc; do sign_nested "$x"; done
sign_nested "$SPK/Autoupdate"
sign_nested "$SPK/Updater.app"
sign_nested "$APP/Contents/Frameworks/Sparkle.framework"
if [ -n "${IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp \
           --entitlements scripts/entitlements.plist \
           --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
  echo "  (ad-hoc signature — set IDENTITY to sign for distribution)"
fi
codesign --verify --deep --strict "$APP" && echo "  signature OK"
echo "  arch: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

echo "✓ $APP  ($VERSION / $BUILD_NUM)"
echo "  open -n \"$APP\"      # -n: a separate instance, leaves an installed copy alone"
echo "  pkill -f \"$PWD/$APP/Contents/MacOS/$APP_NAME\"   # stops only this build"
