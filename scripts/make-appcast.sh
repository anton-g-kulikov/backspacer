#!/bin/bash
# Writes a Sparkle appcast with one item — the release being published — to stdout.
#   scripts/make-appcast.sh <short-version> <build-number> <length> <ed-signature> <dmg-url> <notes-url> [notes.md]
# sparkle:version is CFBundleVersion (the build timestamp, always increasing); shortVersionString is
# the marketing version. With a Markdown notes file (the changelog section) the notes go inline as
# HTML, which is what Sparkle shows in its pane; the GitHub release page stays the "full notes" link.
# Run by release.yml after sign_update; the file ships as a release asset and the site republishes
# it at https://backspacer.dev/appcast.xml.
set -euo pipefail
[ $# -ge 6 ] || { echo "usage: $0 short-version build-number length ed-signature dmg-url notes-url [notes.md]" >&2; exit 2; }
SHORT="$1"; BUILD="$2"; LENGTH="$3"; SIG="$4"; URL="$5"; NOTES="$6"; MD="${7:-}"
DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

# Markdown bullets → a plain HTML list: `code`, **bold**, and the changelog's few entities.
html_notes() {
  python3 - "$1" <<'PY'
import html, re, sys
out = ["<ul>"]
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.startswith("- "): continue
    t = html.escape(line[2:], quote=False)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", t)
    out.append("  <li>" + t + "</li>")
out.append("</ul>")
print("\n".join(out))
PY
}

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Backspacer</title>
    <link>https://backspacer.dev/</link>
    <description>Backspacer releases</description>
    <language>en</language>
    <item>
      <title>Backspacer ${SHORT}</title>
      <pubDate>${DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${SHORT}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>${NOTES}</sparkle:fullReleaseNotesLink>
XML
if [ -n "$MD" ] && [ -s "$MD" ]; then
  echo "      <description><![CDATA["
  echo "<style>body{font:13px -apple-system,system-ui;color:#333;margin:12px 16px}ul{padding-left:18px}li{margin:4px 0}code{font:12px ui-monospace,Menlo,monospace;background:#f2f2f4;padding:1px 4px;border-radius:4px}@media(prefers-color-scheme:dark){body{color:#ddd}code{background:#333}}</style>"
  html_notes "$MD"
  echo "      ]]></description>"
else
  echo "      <sparkle:releaseNotesLink>${NOTES}</sparkle:releaseNotesLink>"
fi
cat <<XML
      <enclosure url="${URL}" length="${LENGTH}" type="application/octet-stream" sparkle:edSignature="${SIG}"/>
    </item>
  </channel>
</rss>
XML
