# Test Documentation

Owner of test intent, strategy and status. Test code lives in `Tests/ReclaimerTests/`
(Swift Testing, run with `swift test`). Behaviour docs live in `_meta/`; this file
says what the tests prove, not how the system works.

## Strategy

- Unit-test the pure Swift logic that guards the disk: the safety gate, catalog
  decoding, preference validation, shell quoting. These run against the real
  `catalog.json` so a bad catalog edit fails CI, not a user's home folder.
- Nothing here runs `rm`, `du` or AppleScript. Disk-touching paths are covered by
  manual verification (below) until a fake shell is introduced.
- The web UI (`web/index.html`) has no automated tests yet — see
  `_meta/project-task-list.md`.

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

## Manual verification (release checklist covers these)

- Signed app launches, scans, and the confirmation dialog lists the right items.
- Delete of one safe entry frees space and the row greys out.
- Admin entry prompts the macOS password dialog; cancel leaves the item untouched.
- Full Disk Access banner opens the right System Settings pane.

## Status

| Suite | Cases | State |
|---|---|---|
| SafetyGateTests | S1–S7 | passing |
| CatalogTests | C1–C9 | passing |
| PrefTests | P1–P3 | passing |
| ShellTests | Q1–Q3 | passing |
| CatalogCommandTests | B1–B3 | passing |
| ItemTests | I1–I11 | passing |
| ProjectRootTests | R1–R6 | passing |
| CommandItemTests | T1–T7 | passing |
| DisposalTests | D1–D5 | passing |
| SchemaTests | V1–V3 | passing |
