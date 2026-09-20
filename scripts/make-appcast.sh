#!/bin/bash
# Writes a Sparkle appcast with one item — the release being published — to stdout.
#   scripts/make-appcast.sh <short-version> <build-number> <length> <ed-signature> <dmg-url> <notes-url>
# sparkle:version is CFBundleVersion (the build timestamp, always increasing); shortVersionString is
# the marketing version. Run by release.yml after sign_update; the file ships as a release asset and
# the site republishes it at https://backspacer.dev/appcast.xml.
set -euo pipefail
[ $# -eq 6 ] || { echo "usage: $0 short-version build-number length ed-signature dmg-url notes-url" >&2; exit 2; }
SHORT="$1"; BUILD="$2"; LENGTH="$3"; SIG="$4"; URL="$5"; NOTES="$6"
DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
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
      <sparkle:releaseNotesLink>${NOTES}</sparkle:releaseNotesLink>
      <enclosure url="${URL}" length="${LENGTH}" type="application/octet-stream" sparkle:edSignature="${SIG}"/>
    </item>
  </channel>
</rss>
XML
