# Reclaimer

A small macOS app that finds the caches, build output and tooling leftovers that
silently eat a developer's disk, sorts them by how safe they are to remove, and
deletes only what you tick — after a confirmation that lists every item.

It grew out of a month of chasing "System Data" on a 245 GB MacBook Air. The
knowledge from that chase lives in `catalog.json`; the app is a thin, careful
shell around it.

```
┌─────────────────────────────────────────────┐
│  web/index.html   (HTML/JS UI, runs in       │
│                    WKWebView or a browser)   │
│         │  {id, op, args}  ▲ reply(id, ok)   │
│  Sources/Reclaimer/Bridge.swift              │
│    resolves catalog ids → paths, runs du /   │
│    find / rm, asks for admin via the system  │
│    dialog, opens Full Disk Access settings   │
│         │                                    │
│  catalog.json  — what to scan, which bucket, │
│                  how to delete, what to warn │
└─────────────────────────────────────────────┘
```

## Buckets

| Bucket | Meaning | UI |
|---|---|---|
| `safe` | Caches and build output every app rebuilds on its own. No cost. | selectable, deletable |
| `regen` | Comes back on the next build/install. Costs one slow build. | selectable, deletable |
| `decide` | Real data or tooling — delete only what you no longer use. | selectable, deletable |
| `keep` | Needed for current work. Listed so the numbers add up. | read-only |
| `locked` | SIP-protected system assets. Can't be deleted by anyone. | read-only |

Entries flagged `manual: true` are measured and explained but never deleted by
the app (e.g. "keep only the iOS DeviceSupport folder for your current phone").
Entries flagged `sudo: true` show an **admin** badge and go through macOS's own
password dialog.

## Safety model

- **The web layer never names a path.** Every disk operation takes a catalog
  entry *id*; `Bridge.swift` resolves it from the bundled `catalog.json`. A bug
  or injection in the UI cannot delete anything the catalog doesn't already
  describe.
- **`isSafeToDelete()`** is a second gate: refuses `/`, the home folder, every
  top-level visible folder in home (`~/Documents`, `~/Projects`, …),
  `~/Library` itself, and anything outside `~/`, `/Library/Developer/` or the
  staged macOS update folder.
- **Every delete goes through a confirmation** listing exactly what will go
  and how much. Nothing is removed by a single click.
- **The size threshold hides, it doesn't just filter.** The "Show ≥" slider
  (10 MB … 10 GB, default 100 MB) removes smaller entries from the list, deselects them, and
  they can't be deleted until the slider is lowered again.
- **Nothing runs as root without the system dialog.** Admin items use
  `do shell script … with administrator privileges`, so the app never sees a
  password and there's no helper tool to trust.
- No App Sandbox (it can't delete outside its container). Hardened runtime is
  on, which is what notarization requires.

## Develop

**UI only** — no Xcode needed. The page falls back to a mock bridge with
random sizes when it isn't inside the app:

```bash
python3 -m http.server 8765      # from the repo root
open http://localhost:8765/web/index.html
```

**The app:**

```bash
scripts/build-app.sh             # → build/Reclaimer.app, ad-hoc signed
open build/Reclaimer.app
```

Right-click → *Inspect Element* works inside the app (WKWebView inspector).
`swift build` alone gives you the bare binary for compile checks; `swift test`
runs the suites in `Tests/` (what they cover: `Tests/test-documentation.md`).

**Adding an entry** is a JSON edit. The fields:

```jsonc
{
  "id": "unique-id",                 // stable; the UI and bridge key on it
  "group": "Xcode & simulators",     // sub-heading inside the bucket
  "bucket": "safe",                  // safe | regen | decide | keep | locked
  "label": "Xcode DerivedData",
  "path": "~/Library/Developer/Xcode/DerivedData",   // or "paths": [...], or "glob": {...}
  "note": "Rebuilt on next build.",  // optional, shown under the label
  "sudo": false,                     // needs admin to measure/delete
  "manual": false,                   // measure + explain, never delete
  "sizeCmd": "…",                    // optional: command printing size in KB
  "infoCmd": "xcrun simctl runtime list",  // optional: shown by the Info button
  "deleteCmd": "xcrun simctl erase all"    // optional: replaces rm -rf <path>
}
```

`glob` finds many paths: `{ "root": "~/Projects", "name": "node_modules", "maxdepth": 4, "type": "d" }`.
Extras: `names` (several), `pathPatterns` (`find -path`), `then` (append a
sub-path to each match), `requireSibling` (`"*.csproj"` — only keep matches
whose parent contains such a file).

## Look

Two skins live in `web/index.html` as separate `<style>` sheets: **Glass**
(default; follows light/dark) and **Terminal**. Switch with the buttons in the
header or View → Glass / Terminal (⌘1 / ⌘2). The choice and the size threshold
are stored in `UserDefaults` (`ui.theme`, `ui.minSize`) through the bridge's
`prefGet` / `prefSet` ops, which accept only those two keys. In a browser,
`?theme=terminal` selects the skin. Keep and Managed-by-macOS start collapsed;
click any bucket header to toggle it.

## Full Disk Access

macOS blocks every process, root included, from reading some `~/Library`
folders (Safari, Mail, Messages, Containers of sandboxed apps) unless the app
has Full Disk Access. Reclaimer detects this and shows a banner with a button
that opens the right System Settings pane. Grant it, then Rescan. Without it,
those entries under-report or show `?`.

## Ship it

Requires an Apple Developer Program membership (Developer ID certificate).
One-time:

1. Xcode → Settings → Accounts → *Manage Certificates* → **+** → *Developer ID Application*.
2. Create an app-specific password at appleid.apple.com.
3. `xcrun notarytool store-credentials Reclaimer --apple-id you@example.com --team-id TEAMID --password <app-specific-password>`

Every release:

```bash
IDENTITY="Developer ID Application: Anton Kulikov (TEAMID)" scripts/build-app.sh
scripts/notarize.sh              # notarizes → staples → DMG → notarizes DMG → staples
```

`build/Reclaimer-<version>.dmg` is what you share. Gatekeeper opens it without
warnings on any Mac running macOS 13 or later.

- With `IDENTITY` set the binary is universal (arm64 + x86_64); dev builds are
  native-only. Override with `UNIVERSAL=0` / `UNIVERSAL=1`.
- The version comes from `git describe --tags` (`v0.2.0` → `0.2.0`), or `0.1.0`
  outside a git repo. Set `VERSION=…` to override.
- If Apple rejects the submission, the script prints the notary log, which
  names every offending file and reason.
- The icon comes from `assets/AppIcon.icns` (regenerate from `assets/AppIcon.svg`).

## Layout

```
catalog.json              the knowledge — what to scan and how safe it is
web/index.html            the UI (single file, no dependencies)
Sources/Reclaimer/        AppDelegate, Bridge, Catalog, Shell, main
scripts/build-app.sh      package → .app
scripts/notarize.sh       sign → notarize → staple → dmg
scripts/entitlements.plist
scripts/mac-storage-review.sh   the original read-only terminal audit
Tests/                    Swift Testing suites + test-documentation.md
_meta/                    how it works, bridge API, decisions, task list, release checklist
CHANGELOG.md
```

Internals: `_meta/system-documentation.md`. Roadmap and status: `_meta/project-task-list.md`.
