# System Documentation

Evergreen description of how Reclaimer works internally. User-facing setup and
usage live in `README.md`; the bridge contract in `api-design.md`; the reasons
behind the design in `architecture-decisions.md`.

## Components

| Piece | Role |
|---|---|
| `catalog.json` | The knowledge: what to measure, which bucket it belongs to, how to delete it, what to warn about. `catalog.schema.json` (JSON Schema 2020-12) describes it — field docs, the bucket enum, and the cross-field rules (`children` ⇒ single `path`, `itemsCmd` ⇔ `deleteItemCmd` with `{key}`, every entry has something to measure or show). Editors validate on the `$schema` line; `SchemaTests` validate in `swift test`. |
| `web/index.html` | The UI: markup and the two theme stylesheets. Carries a Content-Security-Policy (`script-src 'self'`, no inline script), so nothing that reaches the DOM as text can execute. Runs standalone in a browser with a mock bridge. |
| `web/boot.js` | Picks the cached theme before first paint. |
| `web/app.js` | Binds page state to the DOM and the bridge: rendering, scanning, the confirm flows, project folders, About. |
| `web/logic.js` | The page's pure logic — formatting, deletability/disposal predicates, nesting and own-size, threshold visibility, meter segmentation, item naming. No DOM, no state; loaded by the page and tested under Node (`Tests/web`). |
| `Sources/Reclaimer/main.swift` | Entry point. Builds `NSApplication` in code — no storyboard, no nib. |
| `Diagnostics.swift` | The shareable log file (see *Diagnostics*). |
| `AppDelegate.swift` | Window (transparent title bar, full-size content so the traffic lights sit on the page; the measured title-bar height is injected as `--titlebar` before first paint and the page pads itself by it), `WKWebView`, menu bar (View → theme), navigation policy (external links leave the app), debug-run fallbacks. |
| `Bridge.swift` | The only door from JS to the machine. Dispatches ops, resolves catalog ids to paths, runs `du`/`find`/`rm`, enforces the safety gate, stores preferences. |
| `Catalog.swift` | Typed mirror of `catalog.json`; `Resources` locates bundled files. |
| `Shell.swift` | Admin commands: `runAsAdmin` launches Reclaimer's own executable as a helper (`Reclaimer --admin <cmd>`, `AdminHelper` in `main.swift`) which runs `do shell script … with administrator privileges` on *its* main thread — one prompt, attributed to Reclaimer, and the app never blocks (R5). `Shell.spawn` launches with `posix_spawn` in a fresh process group with a clean signal mask, so a timeout can `killpg` the whole tree (SIGTERM, then SIGKILL after 2 s) instead of orphaning `du`/`rm` (R8). `CommandRunner` protocol (`run(_:timeout:login:)`, `runAsAdmin`) with `SystemShell` as the production implementation; `Bridge` takes one at init, tests inject `FakeShell`. Measurement and removal (`du`, `find`, `rm`) run with `login: false` — `/bin/sh` with a fixed system PATH, ~5 ms to start; catalog-defined commands run with `login: true` — the user's login zsh, so `brew`/`xcrun`/`dotnet` resolve, ~0.8 s to start — with the well-known tool prefixes (`/opt/homebrew/bin`, `/usr/local/bin`, dotnet, cargo, bun, pub, `~/.local/bin`) appended to `PATH` as a fallback for shells whose profile doesn't set it (`.zshrc`-only, bash, fish), never ahead of the user's own PATH (R6). |
| `Shell` (enum) | Runs commands through a login `zsh` (so `xcrun`, `brew`, `dotnet` resolve), draining stdout/stderr on dedicated threads (GCD's global queue can be starved by concurrent callers and leave the readers unscheduled) with a timeout; admin commands go through AppleScript's `with administrator privileges`. |

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

- Four JS workers (`SCAN_WORKERS`) call `size {id}` for every entry, slowest
  first: the bridge remembers each entry's last duration (`scan.durations` in
  `UserDefaults`, served by `scanHints`) and `scanOrder` sorts by it, so a
  10-second `du` starts at the beginning instead of the end. The bridge returns
  bytes and the resolved paths. A single path is a plain `du -skxc`; several
  paths (glob matches, path lists, children) go through `xargs -P 2 du -skx`,
  two at a time. Ceiling: 4 workers × 2 = at most eight `du` processes — enough
  to overlap I/O, not enough to strain a laptop. `sizeCmd` entries run their
  command and parse the first token as KB; `glob` entries run `find` with
  `-prune` and optional `then` / `requireSibling` filters.
- Sizes below the "Show ≥" threshold hide the row, untick it, and drop it from
  bucket totals. Rows still measuring stay visible. Empty groups collapse; an
  empty bucket shows "Nothing N or larger."
- Entries nested inside another entry (e.g. pip cache in `~/Library/Caches`)
  are detected from the catalog's static paths. Totals, the meter, the
  selection sum and the confirmation total use each entry's *own* size
  (measured minus direct children) so nothing is counted twice.
- The disk meter is a stacked bar over the volume size: everything-else, then
  locked → keep → decide → regen → safe, so reclaimable space sits next to free.

## Project folders

Catalog globs that look for build output use `"root": "$PROJECTS"` instead of
a fixed folder. The bridge expands it to the user's project folders: the
stored `ui.projectRoots` list, or — when nothing is stored — whichever of
`~/Projects`, `~/Developer`, `~/code`, `~/src`, `~/dev`, `~/work`, `~/repos`,
`~/git`, `~/Documents/GitHub`, `~/Sites` exist. The island under the FDA
notice shows the list; **Add folder…** opens `NSOpenPanel` on the main thread
(the path comes from macOS, not the page), `×` removes one, and either change
rescans only the `$PROJECTS` entries. A root must be a directory inside home,
not home itself and not under `~/Library`. Tests R1–R6.

## Granularity

Entries whose source is many paths are *granular*: `glob` matches, a `paths`
list, or a single `path` with `children: true` (its immediate subfolders).
`size` measures each item (`du -sk` per path; `Bridge.parseDu`) and returns
`items` alongside the total, largest first, each with a host-computed
`display` (a glob match relative to its project folder; a child by the value
a `childLabel` file names — VS Code's `workspace.json` → the project path,
an iOS backup's `Info.plist` → the device name (JSON or, by extension,
property list) — or by its folder name); the Details panel lists them with sizes and — when
the entry is deletable by path — a Delete per item. Entries with a `deleteCmd`
(brew, simctl) are never per-item. Single-path entries without an `infoCmd`
get a read-only breakdown of their contents from Details instead.

`delete {id, item}` re-resolves the entry and refuses any `item` not in that
fresh set, then applies the normal safety gate, then `rm -rf` that one path.
Tests I1–I8 run this against a temp directory used as `home`.

Symbolic links are never delete targets: `remove()` (the single path for
`rm` and trash) `lstat`s every path and refuses a link, so a symlinked
`children` item, `glob.then` target or entry path can't drag its destination
along (I14). The gate separately refuses links whose destination is denied
(S11).

Admin (`sudo`) entries are paths only: the only command that ever runs as root
is an `rm -rf` the bridge builds from gate-checked paths. The schema forbids
`sudo` together with `deleteCmd` / `deleteItemCmd`, C11 checks the shipped
catalog, and the bridge refuses such an entry even if one got in (F11).

Command-listed items work the same way without paths: `itemsCmd` prints one
`key<TAB>label<TAB>KB` line per item (simulators from `simctl list devices -j`,
runtimes from `simctl runtime list -j`, parsed by a `python3` one-liner —
python3 ships with Xcode's tools, `jq` doesn't exist before macOS 15), and
`deleteItemCmd` runs with `{key}` replaced by the shell-quoted key after the
key was found in a fresh `itemsCmd` run. Such entries need no whole-entry
delete; runtimes have none, device contents keep `erase all`. Tests T1–T7
drive the real catalog commands against a fake `xcrun`.

## Deletion

1. The page collects ticked ids (only visible, deletable ones) and opens a
   `<dialog>` listing each label and size.
2. On confirm, `delete {id}` per entry. The bridge re-checks `isDeletable`,
   resolves paths, runs `isSafeToDelete` on each, then disposes of them per
   `Bridge.disposal(of:)`: `decide` entries without `sudo`/`deleteCmd`/
   `itemsCmd` are moved to the Trash with `FileManager.trashItem` (a failure
   is an error, never a fallback to `rm`); everything else is `rm -rf` (or
   the entry's `deleteCmd`). `sudo` entries run via `Shell.runAsAdmin`. The
   reply carries `trashed: true` when applicable; the page then rescans the
   Trash entry so its size reflects the move.
3. The reply carries the bytes measured just before deletion; the row greys
   out and the disk numbers refresh.

Safety gate (`Bridge.isSafeToDelete`), applied to every path before `rm` or
trash: the given path and its symlink-resolved form must both pass; names are
compared case-insensitively (the default file system is). Refused: `/`, home,
every top-level *visible* folder in home, `~/Library`,
`~/Library/{Application Support,Developer,Containers}`, `/Users`, `/Library`,
`/System`, `/Applications`, `/private`, `/opt`; anything outside `~/`,
`/Library/Developer/` or the staged macOS-update folder (which is itself the
target); and at any depth the user-data roots in `Bridge.userDataRoots`
(Documents, Desktop, Pictures, Movies, Music, Public, Mail, Messages,
Keychains, Mobile Documents, CloudStorage, Group Containers, Accounts,
Cookies, Safari, `.ssh`, `.gnupg`) plus any `*.photoslibrary` — except inside
a configured project folder. Tests S1–S11 pin this behaviour.

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

## Diagnostics

`~/Library/Logs/Reclaimer/Reclaimer.log` (`Diagnostics.swift`) is the file a
user attaches to a bug report. Plain text, one line per event, `[info]`,
`[warn]` or `[error]`, rotated once past 1 MB (one `.previous.log` kept).
Written by the host only; nothing is ever sent anywhere. Recorded:
launch (version, build, macOS, arch) and quit; every bridge op except
housekeeping (`catalog`, `disk`, `fdaStatus`, prefs, `projectRoots`,
`appInfo`, `log`) with its subject, outcome and duration; every `rm`/`trash`
and every catalog command that fails (status + stderr); WebKit content-process
terminations (the page is reloaded); the page's own log lines and uncaught
JS errors, tagged `page:`. About → **Reveal log** selects the file in Finder.
Because catalog paths and per-item names appear in it, the log reveals folder
and project names — the About text says so.

## Continuous integration

`.github/workflows/ci.yml` runs `swift test`, a universal release build and the
Node web-logic tests on a macOS 15 runner with Xcode 16 for every push to
`main`, every tag and every pull request, and checks that `catalog.json` parses. Signing and notarization
are not part of CI — they need the local keychain (see `release-checklist.md`).

## Repository layout

```
catalog.json              knowledge; catalog.schema.json describes it
web/index.html            UI markup + CSP; boot.js, app.js (DOM + state glue); logic.js pure logic, tested under Node
Sources/Reclaimer/        app
Tests/ReclaimerTests/     Swift Testing suites (Support/: fixture, MiniSchema validator); Tests/test-documentation.md owns test intent
.github/                  CI workflow, issue/PR templates, CODEOWNERS
CONTRIBUTING.md           how to propose entries; inbound Apache-2.0 terms
SECURITY.md               how to report a deletion-safety problem
scripts/                  build-app.sh, notarize.sh, entitlements.plist, mac-storage-review.sh
assets/                   icon sources and the .icns the build embeds
_meta/                    this file, api-design, architecture-decisions, project-task-list, release-checklist
.claude/                  agent workflow (ignored by git) and launch.json for the UI dev server
```
