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
Fixture: a temp directory used as `home`, holding `Projects/a/node_modules` (1 MB), `Projects/b/node_modules` (2 MB), a nested `Projects/a/node_modules/x/node_modules` (must be pruned), and `Library/Developer/Xcode/iOS DeviceSupport/{17.0,18.0}`. A catalog built from JSON in the test.
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
| ItemTests | I1–I8 | passing |
