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

## Manual verification (release checklist covers these)

- Signed app launches, scans, and the confirmation dialog lists the right items.
- Delete of one safe entry frees space and the row greys out.
- Admin entry prompts the macOS password dialog; cancel leaves the item untouched.
- Full Disk Access banner opens the right System Settings pane.

## Status

| Suite | Cases | State |
|---|---|---|
| SafetyGateTests | S1–S7 | passing |
| CatalogTests | C1–C7 | passing |
| PrefTests | P1–P3 | passing |
| ShellTests | Q1–Q3 | passing |
