#!/bin/bash
# Builds Reclaimer.app into build/ from the SwiftPM package.
#
#   scripts/build-app.sh            → ad-hoc signed (runs on this Mac only)
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
#                                   → signed for distribution; follow with scripts/notarize.sh
#   UNIVERSAL=1 …                   → arm64 + x86_64 binary (default when IDENTITY is set)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Reclaimer"
BUNDLE_ID="${BUNDLE_ID:-com.antonkulikov.reclaimer}"
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
cp -R web "$APP/Contents/Resources/web"
cp catalog.json "$APP/Contents/Resources/catalog.json"
[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod -R u+rwX,go+rX "$APP"   # sources may be 0600; other accounts must be able to read the bundle

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
</dict></plist>
PLIST
echo "APPL????" > "$APP/Contents/PkgInfo"

echo "▸ codesign"
if [ -n "${IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp \
           --entitlements scripts/entitlements.plist \
           --sign "$IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
  echo "  (ad-hoc signature — set IDENTITY to sign for distribution)"
fi
codesign --verify --deep --strict "$APP" && echo "  signature OK"
echo "  arch: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

echo "✓ $APP  ($VERSION / $BUILD_NUM)"
echo "  open -n \"$APP\"      # -n: a separate instance, leaves an installed copy alone"
echo "  pkill -f \"$PWD/$APP/Contents/MacOS/$APP_NAME\"   # stops only this build"
