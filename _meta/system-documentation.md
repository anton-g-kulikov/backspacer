# System Documentation

Evergreen description of how Reclaimer works internally. User-facing setup and
usage live in `README.md`; the bridge contract in `api-design.md`; the reasons
behind the design in `architecture-decisions.md`.

## Components

| Piece | Role |
|---|---|
| `catalog.json` | The knowledge: what to measure, which bucket it belongs to, how to delete it, what to warn about. Schema in README → *Adding an entry*. |
| `web/index.html` | The whole UI: markup, two theme stylesheets, and the JS that renders buckets, scans, filters, and asks the host to delete. Runs standalone in a browser with a mock bridge. |
| `Sources/Reclaimer/main.swift` | Entry point. Builds `NSApplication` in code — no storyboard, no nib. |
| `AppDelegate.swift` | Window, `WKWebView`, menu bar (View → theme), navigation policy (external links leave the app), debug-run fallbacks. |
| `Bridge.swift` | The only door from JS to the machine. Dispatches ops, resolves catalog ids to paths, runs `du`/`find`/`rm`, enforces the safety gate, stores preferences. |
| `Catalog.swift` | Typed mirror of `catalog.json`; `Resources` locates bundled files. |
| `Shell.swift` | Runs commands through a login `zsh` (so `xcrun`, `brew`, `dotnet` resolve), with concurrent pipe draining and a timeout; admin commands go through AppleScript's `with administrator privileges`. |

## Startup

1. `AppDelegate` loads the catalog via `Resources.root` — the app bundle's
   `Resources/` normally; in `DEBUG` builds without a bundle (Xcode ⌘R,
   `swift run`) it falls back to the repo root found from `#filePath`.
2. A `WKWebView` is created with the `reclaimer` script message handler and
   `loadFileURL(web/index.html, allowingReadAccessTo: Resources)`.
3. The page picks the cached theme from `localStorage` before first paint, then
   asks the host (`prefGet theme`, `prefGet minSize`) and applies the stored
   values; then `catalog` → render → `disk` → `fdaStatus` → `scan`.

## Scan

- Three JS workers call `size {id}` for every entry. The bridge returns bytes
  and the resolved paths. `du -skxc` measures static paths; `sizeCmd` entries
  run their command and parse the first token as KB; `glob` entries run `find`
  with `-prune` and optional `then` / `requireSibling` filters.
- Sizes below the "Show ≥" threshold hide the row, untick it, and drop it from
  bucket totals. Rows still measuring stay visible. Empty groups collapse; an
  empty bucket shows "Nothing N or larger."
- Entries nested inside another entry (e.g. pip cache in `~/Library/Caches`)
  are detected from the catalog's static paths. Totals, the meter, the
  selection sum and the confirmation total use each entry's *own* size
  (measured minus direct children) so nothing is counted twice.
- The disk meter is a stacked bar over the volume size: everything-else, then
  locked → keep → decide → regen → safe, so reclaimable space sits next to free.

## Deletion

1. The page collects ticked ids (only visible, deletable ones) and opens a
   `<dialog>` listing each label and size.
2. On confirm, `delete {id}` per entry. The bridge re-checks `isDeletable`,
   resolves paths, runs `isSafeToDelete` on each, then `rm -rf` (or the
   entry's `deleteCmd`). `sudo` entries run via `Shell.runAsAdmin`.
3. The reply carries the bytes measured just before deletion; the row greys
   out and the disk numbers refresh.

Safety gate (`Bridge.isSafeToDelete`), applied to every path before `rm`:
refuses `/`, home, every top-level *visible* folder in home, `~/Library`,
`~/Library/{Application Support,Developer,Containers}`, `/Users`, `/Library`,
`/System`, `/Applications`, `/private`, `/opt`; allows only paths under `~/`,
`/Library/Developer/` or the staged macOS-update folder. Traversal is
normalised first. Tests S1–S7 pin this behaviour.

## Preferences

`prefGet` / `prefSet` store strings in `UserDefaults` under `ui.<key>`. Only
`theme` and `minSize` are accepted; values are capped at 32 characters. The
arm-switch that existed before 0.2.0 was deliberately *not* persisted; with it
gone, nothing about deletion is remembered between launches.

## Themes

Two `<style id="css-glass|css-terminal">` sheets; `applyTheme` enables one and
disables the other. Glass follows the system light/dark; Terminal is dark only.
The View menu (⌘1/⌘2) calls `window.__setTheme`; `menuNeedsUpdate` re-reads
`ui.theme` so the checkmark matches the in-page switcher.

## Full Disk Access

`hasFullDiskAccess` lists `~/Library/Safari`, which is TCC-protected. Without
FDA the page shows a banner whose button opens
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
TCC keys the grant on team ID + bundle ID, so it survives rebuilds only for
Developer ID–signed builds; ad-hoc builds lose it on every rebuild.

## Build and packaging

`scripts/build-app.sh` compiles with SwiftPM (universal when `IDENTITY` is
set), assembles `build/Reclaimer.app` with a generated `Info.plist`, normalises
file modes, and signs (hardened runtime + timestamp with a Developer ID,
ad-hoc otherwise). `scripts/notarize.sh` submits the app, staples, wraps it in
a DMG, submits and staples that. See `release-checklist.md` for the sequence.

## Repository layout

```
catalog.json              knowledge
web/index.html            UI (single file)
Sources/Reclaimer/        app
Tests/ReclaimerTests/     Swift Testing suites; Tests/test-documentation.md owns test intent
scripts/                  build-app.sh, notarize.sh, entitlements.plist, mac-storage-review.sh
assets/                   icon sources and the .icns the build embeds
_meta/                    this file, api-design, architecture-decisions, project-task-list, release-checklist
.claude/                  agent workflow (ignored by git) and launch.json for the UI dev server
```
