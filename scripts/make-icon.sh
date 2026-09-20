#!/bin/bash
# Rasterises assets/AppIcon.svg into assets/AppIcon.icns, assets/preview-512.png and the
# site's icon files. Chrome renders the SVG (ImageMagick's built-in SVG renderer can't do
# gradients); iconutil packs the .icns. Run after editing the SVG.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "needs Google Chrome for the SVG render"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp assets/AppIcon.svg "$TMP/"
printf '<!doctype html><html><head><style>html,body{margin:0;background:transparent}img{display:block;width:1024px;height:1024px}</style></head><body><img src="AppIcon.svg"></body></html>' > "$TMP/icon.html"
echo "▸ render 1024²"
# Headless Chrome sometimes fails to exit after writing the screenshot; a 40 s alarm ends it.
perl -e 'alarm 40; exec @ARGV' "$CHROME" --headless=new --disable-gpu --allow-file-access-from-files --hide-scrollbars --no-first-run \
  --default-background-color=00000000 --window-size=1024,1024 --force-device-scale-factor=1 --virtual-time-budget=2000 \
  --user-data-dir="$TMP/profile" --screenshot="$TMP/1024.png" "file://$TMP/icon.html" >/dev/null 2>&1 || true
[ -s "$TMP/1024.png" ] || { echo "render failed"; exit 1; }
echo "▸ iconset"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for px in 16 32 128 256 512; do
  sips -Z $px "$TMP/1024.png" --out "$SET/icon_${px}x${px}.png" >/dev/null
  sips -Z $((px*2)) "$TMP/1024.png" --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o assets/AppIcon.icns
echo "▸ previews"
sips -Z 512 "$TMP/1024.png" --out assets/preview-512.png >/dev/null
sips -Z 512 "$TMP/1024.png" --out site/assets/icon-512.png >/dev/null
sips -Z 180 "$TMP/1024.png" --out site/assets/apple-touch-icon.png >/dev/null
sips -Z 64  "$TMP/1024.png" --out site/assets/icon-64.png >/dev/null
magick "$TMP/1024.png" -define icon:auto-resize=48,32,16 site/favicon.ico   # browsers ask for /favicon.ico first
cp assets/AppIcon.svg web/icon.svg   # the page header shows the same mark (web/ is copied into the bundle)
echo "  bump the ?v= on the icon URLs in site/index.html so caches miss"
echo "✓ assets/AppIcon.icns, assets/preview-512.png, site/assets/icon-{512,64}.png, apple-touch-icon.png, web/icon.svg"
