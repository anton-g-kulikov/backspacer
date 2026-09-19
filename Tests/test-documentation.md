# Test Documentation

Owner of test intent, strategy and status. Test code lives in `Tests/ReclaimerTests/`
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

### CatalogCommandTests — catalog shell commands, run for real through `Shell.run`
Integration tests: a fake `brew` on `PATH` and a temp Cellar stand in for Homebrew. Nothing touches the real system.
| # | Case | Expect |
|---|---|---|
| B1 | `cache-brew-orphans.infoCmd` with a dry run listing `libfoo` and `user/tap/libbar` (2 MB + 1 MB in the Cellar) | output lists both names and ends with `Total: 3 MB` |
| B2 | same with an empty dry run | output is exactly `No orphaned dependencies.` |
| B3 | the entry has no `sizeCmd` — the check runs only from Details, never during a scan | pass |

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
Validated with a small JSON-Schema subset validator in `Tests/ReclaimerTests/Support/MiniSchema.swift` (type, required, properties, additionalProperties, enum, const, items, minItems, pattern, anyOf, not, dependentRequired, dependentSchemas — the keywords the schema uses).
| # | Case | Expect |
|---|---|---|
| V1 | the shipped `catalog.json` | validates |
| V2 | an entry with an unknown field, an unknown bucket, an `id` with spaces, `children` without `path`, `children` alongside `glob`, `itemsCmd` without `deleteItemCmd`, `deleteItemCmd` without `{key}`, `childLabel` without `children`, no source at all | each rejected, with a message naming the entry's path in the document |
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

### Web logic — `Tests/web/logic.test.js` (Node's `node:test`, run with `node --test Tests/web`)
Pure functions from `web/logic.js` — the page's `index.html` keeps only DOM and state glue. Runs against the real `catalog.json`.
| # | Case | Expect |
|---|---|---|
| J1 | `fmt` | `null` → `—`; 512 000 → `512 KB`; 5 000 000 → `5 MB`; 1.5e9 → `1.5 GB`; 2e9 → `2 GB` (no `.0`) |
| J2 | `esc` | `&`, `<`, `>` escaped; nothing else touched |
| J3 | `deletable` / `itemDeletable` / `trashes` | the D1 matrix, mirrored: `decide`+path → trashes; `safe`, `regen` → not; `decide`+`sudo`, +`deleteCmd`, +`itemsCmd` → not; `manual` never deletable; `deleteItemCmd` makes items deletable even when the entry isn't |
| J4 | `buildNesting` on the shipped catalog | `cache-user`'s direct children are exactly the four caches inside `~/Library/Caches`; each of them has `cache-user` as parent; a grandchild is not a direct child of its grandparent |
| J5 | `ownSize` / `hasSelectedParent` | own = measured − direct children, never negative; a selected ancestor at any depth counts |
| J6 | `isVisible` | unknown size is visible; below the threshold hidden; equal to it visible |
| J7 | `meterSegments` | order `other, locked, keep, decide, regen, safe`; `other` = used − buckets, floored at 0; titles from the catalog |
| J8 | `itemName` | `display` wins, then `label`, then the last two path components |
| J11 | `shuffled` | a permutation of the words; different rngs give different orders; `scanFrame` honours the given list |
| J13 | `scanOrder` | entries sorted by last duration, longest first; unknown durations last, in catalog order; `SCAN_WORKERS` is 4 |
| J14 | `confirmDialog` (R1) | resolves `true` only when the dialog closed with `returnValue === "ok"`; a close without a value (Escape) after a previous "ok" resolves `false` — the stale value is reset before every open |
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

## Manual verification (release checklist covers these)

- Signed app launches, scans, and the confirmation dialog lists the right items.
- Delete of one safe entry frees space and the row greys out.
- Admin entry prompts the macOS password dialog; cancel leaves the item untouched.
- Full Disk Access banner opens the right System Settings pane.

## Status

| Suite | Cases | State |
|---|---|---|
| SafetyGateTests | S1–S7 | passing |
| CatalogTests | C1–C10 | passing |
| PrefTests | P1–P3 | passing |
| ShellTests | Q1–Q3 | passing |
| CatalogCommandTests | B1–B3 | passing |
| ItemTests | I1–I13 | passing |
| ProjectRootTests | R1–R6 | passing |
| CommandItemTests | T1–T8 | passing |
| DisposalTests | D1–D5 | passing |
| SchemaTests | V1–V3 | passing |
| FakeShellTests | F1–F10 | passing |
| Web logic (node) | J1–J14 | passing |
| DiagnosticsTests | L1–L7 | passing |
| ShellModeTests | M1–M5 | passing |
