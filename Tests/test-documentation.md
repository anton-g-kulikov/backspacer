# Test Documentation

Owner of test intent, strategy and status. Test code lives in `Tests/BackspacerTests/`
(Swift Testing, run with `swift test`). Behaviour docs live in `_meta/`; this file
says what the tests prove, not how the system works.

## Strategy

Gotcha: inside `#expect`, literal arithmetic compared with an `Int64?` (`n(x) == 2048 * 1024`)
fails even when the values are equal — bind the expected value to a typed `let` first.

- Unit-test the pure Swift logic that guards the disk: the safety gate, catalog
  decoding, preference validation, shell quoting. These run against the real
  `catalog.json` so a bad catalog edit fails CI, not a user's home folder.
- Nothing here runs `rm`, `du` or AppleScript. Disk-touching paths are covered by
  manual verification (below) until a fake shell is introduced.
- The web UI's pure logic lives in `web/logic.js` and is tested under Node
  (`Tests/web`); `index.html` keeps only DOM and state glue, checked manually
  in the browser (`?theme=` + the mock bridge) and in the app.

## Test cases

### SafetyGateTests — `Bridge.isSafeToDelete`
| # | Case | Expect |
|---|---|---|
| S1 | `/`, `~`, `~/Library`, `~/Documents`, `~/Projects`, `/Users`, `/System`, `/Applications` | refused |
| S2 | `~/Library/Caches`, `~/.cache`, `~/Library/Developer/Xcode/DerivedData`, `/Library/Developer/CoreSimulator/Caches` | allowed |
| S3 | path outside allowed roots: `/opt/homebrew`, `/private/var/vm`, `/Volumes/Other` | refused |
| S4 | top-level visible home folder (`~/Anything`) refused; top-level dot-folder (`~/.gradle`) allowed |
| S5 | traversal: `~/Library/Caches/../../Documents` normalises to a refused path | refused |
| S6 | relative path | refused |
| S7 | every static `path`/`paths` of a deletable catalog entry (with a home-relative or allowed root) passes the gate — the catalog can never name something the gate refuses |
| S12 | glob roots and `children` parents (R27) | every fixed glob root and every `children` parent path in the catalog is inside an allowed root (so their matches/children can pass the gate); a representative match under each glob root (`<root>/x/<name>[/then]`) and a child under each `children` path pass the gate; `$PROJECTS` globs pass for a match inside a configured project folder |
| S8 | user-data deny-list (R3) | refused anywhere under: `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Movies`, `~/Music`, `~/Public`, `~/Library/Mail`, `~/Library/Messages`, `~/Library/Keychains`, `~/Library/Mobile Documents`, `~/Library/CloudStorage`, `~/Library/Group Containers`, `~/Library/Accounts`, `~/Library/Cookies`, `~/Library/Safari`, `~/.ssh`, `~/.gnupg`, and any `*.photoslibrary`; a path inside a configured project folder is exempt (`~/Documents/mycode/app/node_modules` once `~/Documents/mycode` is added as a root) |
| S9 | case folding | `~/library/MAIL/x` is refused on the case-insensitive default file system; `~/Library/Caches` in any case is allowed |
| S10 | roots need a separator | `/System/Volumes/Data/macOS Install Data-2` refused; `…/macOS Install Data/x` allowed |
| S11 | symlinks are resolved first | a symlink inside `~/Library/Caches` that points at `~/Documents` is refused |

### CatalogTests — `Catalog` decoding and invariants (real `catalog.json`)
| # | Case | Expect |
|---|---|---|
| C1 | decodes; `version == 1`; entries non-empty | pass |
| C2 | ids unique | pass |
| C3 | every bucket ∈ {safe, regen, decide, keep, locked} | pass |
| C4 | `isDeletable` is true only for safe/regen/decide, not manual, with a source (`path`/`paths`/`glob`/`deleteCmd`) | matches a hand-built expectation per entry |
| C5 | entries in keep/locked are never deletable | pass |
| C6 | `entry(id)` returns the entry; unknown id → nil | pass |
| C7 | `String.expandingTilde` expands only a leading `~` | `~/x` → `$HOME/x`; `a/~/x` unchanged |
| C9 | every `children: true` entry has a single `path`, no `paths`/`glob`/`deleteCmd` (per-item delete is `rm` on a subfolder) | pass |
| C15 | catalog text is plain (R27): no `<` in any `label`, `note` or bucket `blurb` — they are rendered through `esc()` and would show literally | pass |
| C14 | every entry whose path is under `~/Library/Containers`, `~/Library/Group Containers`, `~/Library/Messages`, `~/Library/Mail`, `~/Library/Safari` or `MobileSync` carries `fda: true`; the new Mail-downloads, Teams-cache and Messages-attachments entries exist with the right buckets | pass |
| C13 | `android-avd` is a `children` entry with `companion: ".ini"`; `companion` only appears with `children` | pass |
| C12 | `cache-logs` is a `children` entry excluding `Backspacer` and `DiagnosticReports` (R21); `exclude` only ever appears with `children` | pass |
| C11 | no entry combines `sudo` with `deleteCmd` or `deleteItemCmd` (R7): admin work is only ever an `rm -rf` the bridge builds from gate-checked paths | pass |
| C10 | app-data revamp shape: `electron-caches` is a `safe` glob with the six cache names and the Service-Worker path pattern; `app-slack` is gone and `vscode-cache` no longer lists `Code/Cache` (both covered by the glob); `cache-user` and `cache-dot` are `children`; `ios-backups` has a plist `childLabel`; `ollama-models` pairs `itemsCmd`/`deleteItemCmd` | pass |
| C8 | Time Machine local snapshots (`regrow-snapshots`) live in `locked`, are not deletable, have no `deleteCmd`, keep their `infoCmd` — macOS purges them itself and the app's free-space figure already counts them | pass |

### PrefTests — `Bridge.prefKey` / `prefValue`
| # | Case | Expect |
|---|---|---|
| P1 | `theme`, `minSize` | accepted, namespaced as `ui.<key>` |
| P2 | any other key (`token`, `NSQuitAlwaysKeepsWindows`, empty) | throws |
| P3 | value longer than 32 chars, or non-string | throws |

### ShellTests — `Shell.q`
| # | Case | Expect |
|---|---|---|
| Q1 | plain path | wrapped in single quotes |
| Q2 | path containing `'` | quote closed, escaped, reopened (`'a'\''b'`) |
| Q3 | path with spaces, `$`, backticks, `;` | inert inside single quotes (no other escaping) |
| Q4 | path with a newline (R27) | stays one shell word: `sh -c "printf %s <quoted>"` prints the original bytes back |

### CatalogCommandTests — catalog shell commands, run for real through `Shell.run`
Integration tests: a fake `brew` on `PATH` and a temp Cellar stand in for Homebrew. Nothing touches the real system.
| # | Case | Expect |
|---|---|---|
| B1 | `cache-brew-orphans.infoCmd` with a dry run listing `libfoo` and `user/tap/libbar` (2 MB + 1 MB in the Cellar) | output lists both names and ends with `Total: 3 MB` |
| B2 | same with an empty dry run | output is exactly `No orphaned dependencies.` |
| B3 | the entry has no `sizeCmd` — the check runs only from Details, never during a scan | pass |
| B4 | `user-screenshots.sizeCmd` (R4) with a fake `HOME`: no `~/Screenshots`, no matching Desktop files | prints `0` (not an aborted command) |
| B5 | same with `Screenshots/s.png` (1 MB) and `Desktop/a.mov` (2 MB), plus an unrelated 5 MB file | prints 3072 (KB) |

### ItemTests — per-item granularity (`Bridge.size` / `delete` / `info` via `handle`)
Fixture: a temp directory used as `home`, holding `Projects/a/node_modules` (1 MB + 1 MB nested), `Projects/b/node_modules` (3 MB), a nested `Projects/a/node_modules/x/node_modules` (must be pruned), and `Library/Developer/Xcode/iOS DeviceSupport/{17.0,18.0}`. A catalog built from JSON in the test.
| # | Case | Expect |
|---|---|---|
| I1 | `size` on a glob entry | `items` = the two matches with per-path bytes; nested one absent; `bytes` = total |
| I2 | `size` on a `children: true` entry | `items` = the two subfolders |
| I3 | `size` on a plain single-path entry | no `items` key |
| I4 | `delete {id, item}` with an item that is not in the fresh resolve (sibling folder, or a path outside home) | throws; nothing removed |
| I5 | `delete {id, item}` with a real match | only that match removed; the other stays; `freedBytes` > 0 |
| I6 | `delete {id, item}` on an entry with `deleteCmd` | throws (custom commands aren't per-item) |
| I7 | `info` on a single-path entry without `infoCmd` | breakdown: one line per child, largest first, human sizes |
| I8 | `Bridge.parseDu` | parses `KB<TAB>path` lines; ignores the trailing `total` line |
| I9 | item `display` | glob matches are shown relative to the project folder they were found in (`a/node_modules`, not `build`); `children` items show the folder name |
| I10 | item order | largest first, for path and command items alike |
| I12 | `childLabel` with a `.plist` file | reads the key from a property list (iOS backup `Info.plist` → "Device Name") |
| I13 | glob with `names` + `pathPatterns` at depth 3 | matches `App/Cache`, `App/Code Cache`, `App/Service Worker/CacheStorage`; not `App/Other`, not `App/Cache/inner` (pruned) |
| I14 | symlinks are refused as delete targets (R9) | a symlinked child of a `children` entry is listed but `delete {id, item}` throws and neither the link nor its target is touched; a symlinked `glob.then` target likewise; a whole-entry delete whose `path` is a symlink throws |
| I15 | `exclude` on a `children` entry (R21) | excluded names are not listed as items, the total is the sum of the listed items, and a whole-entry delete removes the listed children only — the excluded folders and the parent stay |
| I16 | `companion` on a `children` entry (AVDs) | children are listed by their stem (`Pixel_7`, not `Pixel_7.avd`); deleting one removes the folder *and* its `<stem>.ini`; a stray `.ini` without a folder is left alone; a companion that is a symlink is refused |
| I11 | `childLabel: {file, keys}` | a child's label is read from `<child>/<file>` JSON, first present key, `file://` stripped and home shown as `~`; a child without the file, or with none of the keys, falls back to its folder name |

### ProjectRootTests — configurable project folders (`$PROJECTS`)
Fixture: temp home with `Projects/a/node_modules`, `Developer/b/node_modules`, `Library/Caches/x/node_modules`, `Documents/mycode` (not a candidate name), a file `notes.txt`; an isolated `UserDefaults` suite.
| # | Case | Expect |
|---|---|---|
| R1 | no stored preference | roots = the common names that exist (`~/Projects`, `~/Developer`), in candidate order; `~/code` etc. absent |
| R2 | `isValidProjectRoot` | accepts an existing directory under home (not a candidate); rejects home itself, `~/Library`, anything under `~/Library`, a path outside home, a file, a missing path |
| R3 | `addProjectRoot(path:)` | persists; adding the same folder twice keeps one; adding an invalid one throws and leaves the list unchanged |
| R4 | `removeProjectRoot` | removes a listed root; a path not in the list throws |
| R5 | glob with `"root": "$PROJECTS"` | matches under every root (`Projects/a/…`, `Developer/b/…`); never under `~/Library` |
| R6 | `projectRoots` op reply | `{roots: [{path, display}]}` with `display` using `~` |

### CommandItemTests — command-listed items (`itemsCmd` / `deleteItemCmd`)
Fixture: a fake `xcrun` first on `PATH` that answers `simctl list devices -j` and `simctl runtime list -j` with fixture JSON (two available devices + one unavailable; two runtimes, one not deletable) and appends every other invocation to a log file. The real `catalog.json` entries are used, so the actual command strings are exercised.
| # | Case | Expect |
|---|---|---|
| T1 | `size` on `xcode-simdevices` | `items` = the two available devices: key = UDID, label "iPhone 17 Pro · iOS 26.5", bytes from `dataPathSize`; the unavailable one absent |
| T2 | `size` on `xcode-runtimes` | `items` = the deletable runtime only: key, label "iOS 26.5 (23F77)", bytes from `sizeBytes`; `bytes` = sum |
| T3 | `delete {id, item: <unknown key>}` | throws; the fake `xcrun` log shows no `erase`/`delete` call |
| T4 | `delete {id, item: <valid UDID>}` on devices | log shows `simctl erase <udid>`; `freedBytes` = that device's bytes |
| T5 | `delete {id, item: <valid key>}` on runtimes | log shows `simctl runtime delete <key>` |
| T6 | `Bridge.parseItems` | parses `key\tlabel\tKB`; skips malformed lines |
| T8 | `ollama-models.itemsCmd` against a fake `ollama` printing the `NAME ID SIZE MODIFIED` table | items keyed by model name with KB from `4.9 GB` / `815 MB`; the header row skipped |
| T7 | catalog invariant: every entry with `itemsCmd` also has `deleteItemCmd` containing `{key}`, and vice versa | pass |

### DisposalTests — Trash vs permanent
Fixture: temp home with a `safe` cache, a `decide` folder, a `decide` `children` folder with two subfolders, a `decide` admin path, a `decide` entry with a `deleteCmd`; a recording trasher injected into the bridge (the real one is `FileManager.trashItem`).
| # | Case | Expect |
|---|---|---|
| D1 | `Bridge.disposal(of:)` | `decide` + path → `.trash`; `safe` / `regen` → `.permanent`; `decide` + `sudo` → `.permanent`; `decide` + `deleteCmd` → `.permanent` |
| D2 | whole-entry delete of a `decide` folder | the trasher receives that path, the source is gone, reply has `trashed: true`; nothing is `rm`'d |
| D3 | per-item delete on a `decide` `children` entry | only that child is trashed; the sibling stays |
| D4 | the trasher throws | the error surfaces, the source is untouched — no fallback to `rm` |
| D5 | whole-entry delete of a `safe` folder | removed permanently, trasher not called, reply has no `trashed` |

### SchemaTests — `catalog.schema.json`
Validated with a small JSON-Schema subset validator in `Tests/BackspacerTests/Support/MiniSchema.swift` (type, required, properties, additionalProperties, enum, const, items, minItems, pattern, anyOf, not, dependentRequired, dependentSchemas — the keywords the schema uses).
| # | Case | Expect |
|---|---|---|
| V1 | the shipped `catalog.json` | validates |
| V2 | an entry with an unknown field, `sudo` together with `deleteCmd`, an unknown bucket, an `id` with spaces, `children` without `path`, `children` alongside `glob`, `itemsCmd` without `deleteItemCmd`, `deleteItemCmd` without `{key}`, `childLabel` without `children`, no source at all | each rejected, with a message naming the entry's path in the document |
| V3 | the validator itself: a handful of positive/negative cases per keyword | as expected (guards against the validator silently accepting everything) |

### FakeShellTests — the bridge against a scripted shell
A `FakeShell` (`CommandRunner`) records every command and answers from a script; nothing real runs. Covers what the temp-directory suites can't: failures, timeouts, admin routing, and the exact command text.
| # | Case | Expect |
|---|---|---|
| F1 | `size` on a path entry | runs `du -skxc '<path>' 2>/dev/null` (quoted); bytes = the `total` line |
| F2 | `du` fails (non-zero, empty output) | bytes 0, no error |
| F3 | `rm` fails with stderr | `delete` throws with that stderr; nothing else runs |
| F4 | `sudo` entry | `delete` goes through `runAsAdmin`, never `run`; a cancelled dialog (status −128, "cancelled") surfaces as an error |
| F5 | glob resolution | runs `find '<root>' -maxdepth N -type d \( -name 'x' \) -prune -print0`; NUL-separated output with spaces in names parses into paths |
| F6 | `itemsCmd` prints garbage | items empty, no error |
| F7 | `sizeCmd` prints non-numeric output | bytes `null` |
| F8 | `deleteCmd` entry | the custom command runs verbatim (no `rm`) |
| F9 | `size` on an entry with several paths | one `xargs -0 -P 2 -n 1 du -skx` over NUL-separated quoted paths; total = sum of the per-path lines; items keep per-path bytes. Ceiling: 4 workers × 2 = at most 8 `du` processes during a scan |
| F10 | `size` on a single-path entry | still a plain `du -skxc` (no xargs) |
| F12 | `fda: true` entries | without Full Disk Access (no `~/Library/Safari` in the fixture home) `size` returns `bytes: null` and runs no `du`; with it, `du` runs as usual |
| F11 | a `sudo` entry with a `deleteCmd` / `deleteItemCmd` (built in the test; the catalog forbids it) | `delete` throws; nothing reaches `runAsAdmin`; `run` is never called with the command |

### Web logic — `Tests/web/logic.test.js` (Node's `node:test`, run with `node --test Tests/web`)
Pure functions from `web/logic.js` — the page's `index.html` keeps only DOM and state glue. Runs against the real `catalog.json`.
| # | Case | Expect |
|---|---|---|
| J1 | `fmt` | `null` → `—`; 512 000 → `512 KB`; 5 000 000 → `5 MB`; 1.5e9 → `1.5 GB`; 2e9 → `2 GB` (no `.0`) |
| J2 | `esc` | `&`, `<`, `>`, `"`, `'` escaped (R2: values go into double- and single-quoted attributes); nothing else touched |
| J15 | hostile names (R2) | `esc('x" onmouseover="alert(1)')` contains no `"`; round-trips through an attribute unchanged; `index.html` carries a CSP `<meta>` with `script-src 'self'` and no inline `<script>` blocks (inline handlers are inline script) |
| J3 | `deletable` / `itemDeletable` / `trashes` | the D1 matrix, mirrored: `decide`+path → trashes; `safe`, `regen` → not; `decide`+`sudo`, +`deleteCmd`, +`itemsCmd` → not; `manual` never deletable; `deleteItemCmd` makes items deletable even when the entry isn't |
| J4 | `buildNesting` on the shipped catalog | `cache-user`'s direct children are exactly the four caches inside `~/Library/Caches`; each of them has `cache-user` as parent; a grandchild is not a direct child of its grandparent |
| J5 | `ownSize` / `hasSelectedParent` | own = measured − direct children, never negative; a selected ancestor at any depth counts |
| J6 | `isVisible` | unknown size is visible; below the threshold hidden; equal to it visible |
| J7 | `meterSegments` | order `other, locked, keep, decide, regen, safe`; `other` = used − buckets, floored at 0; titles from the catalog |
| J8 | `itemName` | `display` wins, then `label`, then the last two path components |
| J11 | `shuffled` | a permutation of the words; different rngs give different orders; `scanFrame` honours the given list |
| J13 | `scanOrder` | entries sorted by last duration, longest first; unknown durations last, in catalog order; `SCAN_WORKERS` is 4 |
| J14 | `confirmDialog` (R1) | resolves `true` only when the dialog closed with `returnValue === "ok"`; a close without a value (Escape) after a previous "ok" resolves `false` — the stale value is reset before every open |
| J17 | `taglineText` | `0`/`undefined` → the plain tagline; otherwise `I got some [<fmt(bytes)> of space] if you need it`; `RECLAIMABLE` is exactly `safe, regen, decide` |
| J19 | `splitItems` | items at or above the threshold (or unmeasured) are shown; the rest are set aside with their byte total; a zero threshold hides nothing |
| J18 | `updateText` | newer → "X is available." plus a Download link; current → "You’re up to date."; no result → the error text; links only when there is something to get |
| J16 | `rowSizeText` with an unknown size on an FDA entry | `needs access`; unknown size elsewhere stays `—` |
| J12 | `rowSizeText` | `in Trash` for a trashed row; otherwise `fmt` |
| J10 | `scanFrame` | the verb changes every 8 ticks and wraps; dots cycle 0→3; 3–8 distinct words |
| J9 | catalog consistency | every entry with `itemsCmd` is `granular` and `hasInfo`; every `children` entry is `granular` |

### DiagnosticsTests — the log file users can share
| # | Case | Expect |
|---|---|---|
| L1 | `Diagnostics.log(level, message)` | appends `YYYY-MM-DD HH:MM:SS [level] message`; creates the folder and file on first use |
| L2 | rotation | when the file exceeds the limit, it is renamed to `.previous.log` and a fresh file starts; only one previous copy is kept |
| L3 | messages are one line | embedded newlines are collapsed to `⏎` |
| L4 | bridge ops are logged | a successful op logs `op id ok (ms)`; a failing op logs the error; `catalog`/`disk`/`fdaStatus`/`prefGet` chatter is not logged |
| L5 | the page's `log` op | `{level, message}` from the page lands in the file with a `page` tag; an unknown level becomes `info` |
| L7 | scan hints | after `size` ops, `scanHints` returns each entry's last duration in ms (persisted in `UserDefaults` under `scan.durations`); unknown entries absent |
| L6 | `revealLog` op | replies with the log path (Finder reveal is a side effect not asserted) |

### ShellModeTests — plain shell for measurement, login shell for tools
Baseline 2026-09-20: `zsh -lc true` 815 ms, `/bin/sh -c true` 5 ms; a 63-entry scan spent 101 s in shell startup.
| # | Case | Expect |
|---|---|---|
| M1 | `Shell.run(…, login: false)` | runs in `/bin/sh` with the fixed system PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), not the user's profile; `$0` is `/bin/sh` |
| M2 | `Shell.run(…, login: true)` | runs in a login zsh (the user's PATH, e.g. Homebrew's bin) |
| M3 | routing (via `FakeShell`) | `du`/`find`/`rm` from `size`, glob resolution, per-item measurement and permanent deletes run with `login: false`; `sizeCmd`, `infoCmd`, `deleteCmd`, `itemsCmd`, `deleteItemCmd` run with `login: true` |
| M4 | the breakdown (`info` without `infoCmd`) works in plain sh | no `setopt`; a folder with no dotfiles still lists its children |
| M5 | ten plain-shell `du`s on an empty folder finish in under 1 s total | guards against a regression back to the login shell |
| M9 | timeout kills the whole process group (R8) | `sh -c "sleep 31.7; echo x"` with a 1 s timeout returns within ~2 s, not `ok`, with no output — and no `sleep 31.7` process survives (`pgrep -f`) |
| M10 | normal completion is unaffected | a quick command still returns its stdout/stderr and exit status through the new spawner; output larger than a pipe buffer (200 KB) is read fully |
| M8 | tool fallback PATH (R6) | every catalog command is prefixed with `export PATH=…` that keeps the user's `$PATH` first and appends the known tool prefixes (`/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`, `/usr/local/share/dotnet`, `~/.dotnet/tools`, `~/.cargo/bin`, `~/.bun/bin`, `~/.pub-cache/bin`, `~/.local/bin`); a test `pathPrefix` still comes before `$PATH`; measurement commands (`du`, `find`) get no such prefix |
| M6 | `Shell.adminScript(for:)` (R5/R27) | wraps the command in `do shell script "…" with administrator privileges`, escaping backslashes and double quotes; a path with `'` and `"` survives the round trip through `Shell.q` + AppleScript quoting |
| M7 | `Shell.runAsAdmin` structure (R5) | the privileged command runs in a helper subprocess — Backspacer's own executable launched with `--admin <command>` — never through `NSAppleScript` on the app's main thread. Pinned by the `runAsAdmin(_:helper:spawn:)` seam: the spawner receives the helper path and `[--admin, command]`; a helper exit of 128/"cancelled" surfaces as a failed result. M7b: `AdminHelper.main` returns 64 for anything but `--admin <command>` |

### Web accessibility — `Tests/web/a11y.test.js` (static checks over `index.html` / `app.js`)
The DOM can't run under Node, so these pin the templates; the browser's accessibility tree is the live check (recorded in the task list when a change lands).
| # | Case | Expect |
|---|---|---|
| A1 | bucket headers (R10) | the header template renders a `<button>` inside the `<h2>` with `aria-expanded` and `aria-controls`; the click handler toggles `aria-expanded`; the section body carries the matching `id` |
| A2 | names (R11) | row checkboxes get `aria-label` from the entry label; the bucket "all" checkbox is labelled "Select all in <bucket>"; the root chip's `×` has an `aria-label` |
| A3 | slider (R12) | `#thr` has `aria-label`; `setThreshold` sets `aria-valuetext` to the formatted size |
| A4 | live region (R13) | a visually-hidden `aria-live="polite"` element exists; `announce()` is called on scan start/end and after deletes; `#log` has `role="log"`; the Scan button is never `disabled` while scanning (it uses `aria-busy` and ignores clicks) |
| A5 | meter (R16) | `#diskBar` has `role="img"` and `updateMeter` writes an `aria-label` summarising the segments |
| A7 | contrast (R14) | computed from the CSS tokens against each theme's panel background: `--muted` ≥ 4.5:1 in Glass light, Glass dark and Terminal; `--faint` ≥ 3.3:1 (Glass light) and ≥ 4.5:1 (Glass dark, Terminal); a `@media (prefers-contrast: more)` block raises both |
| A8 | reduced motion (R15) | both themes have a `@media (prefers-reduced-motion: reduce)` block that stops the blink animations and transitions; `startScanWords` shows a static "Scanning…" when the media query matches |
| A9 | scrollbar | the thumb is styled for `main`, `.info-out` (Details) and `.panel` (Log/About) in both themes (plus a dark-mode override in Glass); the scrollbar is never hidden (`display: none` / zero width) — it stays a visible affordance, keyboard scrolling untouched |
| A10 | drag region and selection sweep | `app.js` has a `mousedown` listener that calls `bridge.call('dragWindow')` on the header and `preventDefault`s outside `SELECTABLE_OR_INTERACTIVE` (which names `.path` and `input`, so paths stay selectable and controls keep their default) |
| A11 | right-click target (ADR-10) | `app.js` has a `contextmenu` listener that sends `contextTarget {id, item}` — selectors only, never a path; Details items carry `data-item` |
| A12 | scan button and header layout | `startScanWords` writes the verb frames to `#scan` (static "Scanning…" under Reduce Motion); nothing references `#host`; `#scan` is its own grid cell after `.controls`; the brand column is `minmax(0, 360px)` in Glass and `minmax(0, 400px)` in Terminal (monospace) with `.controls { justify-self: center }`, a `min-width` on the busy button, and a `max-width: 959px` block that stacks the brand over the controls |
| A13 | update check UI | About has `<p class="upd">` with the `#checkUpd` button and an `aria-live` `#updResult`; `app.js` wires the click and `window.__checkUpdates` (for the app menu); the check is never called at init |
| A14 | Details threshold | `renderItems` splits with `splitItems(items, minBytes())`, ends with a `data-showsmall` button ("N smaller items, X — below Y") that reveals them; `applyThreshold` re-renders open lists |
| A15 | default threshold | `state.thr` is 0 (10 MB), the slider starts at 0 with `aria-valuetext="10 MB"`, the label reads 10 MB |
| A16 | automatic check UI | `#updNotice` sits between Log and About; About has the `#autoUpd` opt-out bound to `prefSet autoUpdateCheck`; `autoCheckUpdates()` runs once per session right after the first scan completes, never at init |
| A6 | states (R17) | Details buttons toggle `aria-expanded`; Log/About tabs carry `aria-expanded`; theme buttons carry `aria-pressed`; the dialog has `aria-labelledby`/`aria-describedby`; a `:focus-visible` rule exists in both themes; badges are ≥ 11 px; About's heading is an `<h3>` after the page's `<h2>`s; paths are selectable |

### Window drag — `Tests/BackspacerTests/WindowDragTests.swift`
| # | Case | Expect |
|---|---|---|
| G1 | `dragWindow` op | replies `{ok: true}`, is not logged (one per mouse-down), and is a no-op when the bridge has no window |

### Context menu — `Tests/BackspacerTests/ContextMenuTests.swift`, `PathActionTests.swift`
| # | Case | Expect |
|---|---|---|
| X1 | WebKit's text menu | of Look Up, Translate, Search, Copy, Copy Link with Highlight, Share, Writing Tools, Speech, Services, Inspect Element only Search with Google, Copy and Inspect Element survive `PageView.trim` |
| X2 | the page-background menu | Back / Forward / Reload are dropped entirely (no menu) |
| X5 | path action items | `pathItems` yields `New Terminal at Folder` carrying the target as `representedObject`; a target older than 2 s or `nil` yields nothing |
| O1 | `open` op on an entry | opens the entry's first resolved path with the opener (`.terminal`) and replies `{path}` |
| O2 | `open` op on a Details item | the selector must be one of the entry's current items; a foreign path or `/etc` is refused and nothing opens |
| O3 | `open` op's app | only `with: "terminal"` is accepted; anything else or nothing is refused |

### Update check — `Tests/BackspacerTests/UpdateCheckTests.swift`
| # | Case | Expect |
|---|---|---|
| U1 | release JSON | `Updates.parse` yields version without the `v`, the release page, and the `.dmg` asset's download URL |
| U2 | `isNewer` | numeric per component (0.10.0 > 0.9.0), equal is not newer, `1.0` == `1.0.0`, a `-N-gHASH` dev suffix is ignored |
| U3 | `checkUpdate` op | requests exactly `releases/latest` via the injected fetcher; replies `{current, latest, newer, url}` with the DMG URL; `newer` false when versions match |
| U5 | `autoCheckUpdate` throttle | first call fetches and reports; a second call within 24 h replies `skipped: recent` without a request; after a day it fetches again |
| U6 | opt-out | with `ui.autoUpdateCheck` = "0" the automatic check replies `skipped: off` and makes no request; the manual `checkUpdate` still works |
| U7 | quiet failure | a failed fetch replies `skipped: failed` instead of throwing |
| U4 | failures | a thrown fetch or a non-release body makes the op throw with a message that names GitHub |
| N3 | test hygiene | every `Bridge(` in the test target passes `diagnostics:` (the suite must never write to `~/Library/Logs/Backspacer`) |

### Release workflow — `Tests/web/release.test.js` (shape checks over `release.yml` and `notarize.sh`)
| # | Case | Expect |
|---|---|---|
| Y1 | trigger | `v*` tags only; no branches, no pull_request |
| Y2 | permissions | exactly `contents: write` and `id-token: write` |
| Y3 | supply chain | every `uses:` pinned to a 40-hex commit SHA |
| Y4 | order | `shell: bash` (pipefail); swift tests → node tests → keychain → build → notarize → release, in that order |
| Y5 | keychain | created with a random password, the certificate imported with the secret, deleted in an `if: always()` step; the login keychain is never touched |
| Y6 | notarization | credentials come from `NOTARY_*` env (the three secrets), never `--keychain-profile` in CI; `notarize.sh` builds `AUTH` from the env when set, else from the profile, and never echoes the password |
| Y7 | artefact | DMG hashed with `shasum -a 256`, the hash in the notes, the DMG as the asset, Gatekeeper asked first, `attest-build-provenance` on the DMG |

### Navigation delegate — `Tests/BackspacerTests/NavigationDelegateTests.swift`
| # | Case | Expect |
|---|---|---|
| V1 | policy selector | `AppDelegate` responds to `webView:decidePolicyForNavigationAction:decisionHandler:` — under Swift 6 a completion-handler type that isn't `@MainActor @Sendable` "nearly matches", compiles, and is never called (shipped in 0.8.0–0.9.1: links opened inside the window) |
| V2 | the other callbacks | `webViewWebContentProcessDidTerminate:` on the app delegate and `userContentController:didReceiveScriptMessage:` on the bridge are real ObjC selectors |

### Brand — `Tests/BackspacerTests/BrandTests.swift` and `Tests/web/brand.test.js` (ADR-20)
| # | Case | Expect |
|---|---|---|
| N1 | standard log path | `Diagnostics.standard.file` ends in `Library/Logs/Backspacer/Backspacer.log` |
| N2 | bridge channel | `Bridge.handlerName == "backspacer"` |
| K1 | page | `<title>Backspacer</title>`; the wordmark is a plain `<h1>Backspacer</h1>` (no `(y)` in the app); About heading and license paragraph name Backspacer; no trace of the old name in `index.html` |
| K2 | page ↔ Swift | `messageHandlers.backspacer`, `window.__backspacerReply`; the mock bridge's log path is `~/Library/Logs/Backspacer/Backspacer.log`; no old name in `app.js`/`logic.js`/`boot.js` |
| K3 | `build-app.sh` | `APP_NAME="Backspacer"`, bundle id `com.antonkulikov.backspacer` |
| K4 | `notarize.sh` | `build/Backspacer.app`, keychain profile `Backspacer`, `Backspacer-$VERSION.zip/.dmg`, volume `Backspacer` |
| K5 | LICENSE and catalog | the preamble reserves "Backspacer"; `cache-logs` excludes `Backspacer` (its own log folder) |
| K7 | tagline | `.brand .text` stacks `<h1>Backspacer</h1>` over `<span class="tagline">I got some if you need it</span>` (no `#host` slot any more); the page never names the band; `updateTotals` rewrites it with `taglineText(sum of bucketTotal over RECLAIMABLE)`, so the number always equals the sum of the three bucket badges and moves with every measured size |
| K8 | header icon | `.brand` starts with `<img class="mark" src="icon.svg" alt="">`; `web/icon.svg` is byte-identical to `assets/AppIcon.svg` and `make-icon.sh` refreshes it; 42 px in Glass, `display: none` in Terminal; CSP `img-src 'self'` |
| K6 | old-name guard | a case-insensitive `git grep` for the old name lists only the allow-listed history files (CHANGELOG, README note, ADRs, task log, this test, the site test) |

### Site — `Tests/web/site.test.js` (static checks over `site/index.html` and `pages.yml`)
The suite skips while `site/index.html` is absent and fails under `SITE_REQUIRED=1`, which the Pages workflow sets.
| # | Case | Expect |
|---|---|---|
| W1 | head | `lang`, charset, viewport, a `Backspacer…` title, a description ≥ 60 chars, `og:title/description/image/url`, `twitter:card`, an icon, a CSP starting `default-src 'none'` |
| W2 | assets | every local `src`/`href`/`srcset` resolves under `site/`; `og:image` is a site file on the canonical host |
| W3 | links | download → `releases/latest` in the markup with a `download` attribute; the script rewrites `href` to the release's `browser_download_url` (never opens it itself); source → the repo; a separate "Release notes" link to the release page |
| W4 | catalog copy | every bucket title and blurb from `catalog.json` appears verbatim |
| W5 | groups | every `data-group` names a real catalog group; the entry count in the copy equals `entries.length` |
| W6 | license (ADR-14) | never "open source"; "free for noncommercial use"; links to the PolyForm text and `LICENSE` |
| W7 | accessibility | one `h1`, skip link, `main`/`nav` landmarks, `alt` on every image, a name or state on every button, `:focus-visible`, reduced-motion and dark-scheme media queries |
| W8 | wordmark | a plain `<h1>Backspacer</h1>`; no `(y)` or `(y/n)` anywhere (the device was dropped with the app's wordmark); the old name appears nowhere |
| W10 | tagline | "I got some if you need it." once under the `h1` and in `og:description`; the band and track are never named |
| W11 | CSP | the sha256 hashes cover both `<style>` sheets and the one `<script>`; no `unsafe-*`, no event handlers, no `style` attributes |
| W13 | Homebrew | the exact two-step install command once in `<code id="brew">`, a Copy button with an accessible name using the clipboard API, and the README carrying the identical string |
| W14 | SEO | `robots.txt` allowing all with the sitemap URL, `sitemap.xml` listing the page, `404.html` (noindex, links home), JSON-LD `SoftwareApplication` (macOS, free offer, download URL, license, no hardcoded version), a search-phrase kicker above the brand H1, Twitter card tags, description 120–158 chars, title ≤ 60 |
| W15 | reveal hero | the hero holds the System Data row and a findings card (≥ 6 `frow` rows with bucket class and a size, a header total, three `ftotals`), no image; the old `.vs` grid is gone; the real screenshot is a full-width `figure.shot.app` with a caption inside `#how` |
| W12 | look switcher | a `role="group"` "Look" with Glass / Terminal buttons carrying `aria-pressed`; `css-glass` and `css-terminal` sheets, the latter scoped to `:root[data-skin="terminal"]`; the script sits in `<head>` and reads `localStorage` (guarded) or `?theme=` before first paint; a terminal screenshot `<source>` the script enables |
| W9 | workflow | `pages.yml`: pushes to `main` on `site/**`, minimal permissions, SHA-pinned actions, uploads `site`, runs the site tests with `SITE_REQUIRED: 1` |

## Manual verification (release checklist covers these)

- Signed app launches, scans, and the confirmation dialog lists the right items.
- Delete of one safe entry frees space and the row greys out.
- Admin entry prompts the macOS password dialog; cancel leaves the item untouched.
- Full Disk Access banner opens the right System Settings pane.

## Status

| Suite | Cases | State |
|---|---|---|
| SafetyGateTests | S1–S12 | passing |
| CatalogTests | C1–C15 | passing |
| PrefTests | P1–P3 (P1 × theme, minSize, autoUpdateCheck) | passing |
| ShellTests | Q1–Q4 | passing |
| CatalogCommandTests | B1–B5, T1–T8 | passing |
| ItemTests | I1–I16 | passing |
| ProjectRootTests | R1–R6 | passing |
| BrandTests | N1–N3 | passing |
| NavigationDelegateTests | V1–V2 | passing |
| UpdateCheckTests | U1–U7 | passing |
| WindowDragTests | G1 | passing |
| ContextMenuTests | X1, X2, X5 | passing |
| PathActionTests | O1–O3 | passing |
| CommandItemTests | T1–T8 | passing |
| DisposalTests | D1–D5 | passing |
| SchemaTests | V1–V3 | passing |
| FakeShellTests | F1–F12 | passing |
| Web logic (node) | J1–J19 | passing |
| Web accessibility (node) | A1–A16 | passing |
| Site (node) | W1–W15 | passing |
| Brand (node) | K1–K8 | passing |
| Release workflow (node) | Y1–Y7 | passing |
| DiagnosticsTests | L1–L7 | passing |
| ShellModeTests | M1–M10 | passing |
