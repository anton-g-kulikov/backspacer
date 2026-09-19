# Project Task List

Temporal: active work, queued tasks, roadmap. Status lives here and nowhere else.

## Active

_(none)_

## Queued

- **Scan speed, round two.** After ADR-16 the shell overhead is gone; the
  remaining cost is real `du` I/O: `proj-node-modules` 16 s, iOS/Android build
  output 3–4 s each, DerivedData 4 s (2026-09-20, 27 s wall). Options: more
  than three workers (du is I/O-bound), measure glob matches in parallel,
  or show the total early and refine per item.
- **"Crashed but returned" report** (2026-09-20, after emptying the Trash and
  rescanning): no crash report existed; likely a WebKit content-process
  termination, now logged and auto-reloaded. Wait for the next occurrence
  with the log.

- **App data revamp** (grounded 2026-09-20 on this Mac). Findings: the
  Electron cache pattern (`<app>/Cache`, `Code Cache`, `GPUCache`, `DawnCache`
  under `~/Library/Application Support`) is small except Claude (300 MB); the
  big app folders are Code/User (workspaceStorage, covered), Notion/Partitions
  2.2 GB, Steam/Steam.AppBundle 1.2 GB, Figma/DesktopProfile 0.9 GB,
  Google/GoogleUpdater 0.8 GB, Code/WebStorage 0.9 GB + chatDictationModels
  0.8 GB, zoom.us/CefPlugin+asr 0.4 GB, Slack/Service Worker 0.4 GB; in
  `~/Library/Caches`: com.openai.codex 1.3 GB, github-copilot-sdk + copilot
  0.6 GB, notion updaters 0.5 GB, electron 0.2 GB. Plan: one glob entry for
  Electron caches (per-app items, `regen`), re-bucket app *caches* from
  `decide` to `regen` (Slack, Notion local cache, Telegram media) so they are
  removed rather than trashed, keep real data in `decide`, add entries for
  iOS device backups (`MobileSync/Backup`, `children`), Ollama models
  (`~/.ollama`), JetBrains caches, browser caches (Chrome/Firefox/Arc/Brave),
  Spotify cache, Zoom, Teams, Discord, Adobe caches — each verified against a
  real install or documented location. Show an "in Trash" state on rows that
  were moved rather than a size of 0.


- **AVD per-item delete** needs to remove `<name>.avd` and `<name>.ini`
  together — a two-path item; decide whether `children` grows a sibling rule
  or AVDs use `itemsCmd`.


## Roadmap (from the 0.1.0 README)

- "Explain" panel per entry with the full reasoning from the catalog notes.
- Simulator runtime deletion from the UI (`xcrun simctl runtime delete <id>`),
  once the info output is parsed into a picker.
- Per-project view for `~/Projects` with last-touched dates.
- Optional launch-at-login menu-bar mode that warns below a free-space threshold.
- Hold-to-confirm on the dialog's Delete button (a second gate, if wanted after ADR-5).

## Done

- 2026-09-20 — Plain `/bin/sh` for measurement, login zsh only for catalog commands (ADR-16; tests M1–M5). Scan 38 s → 27 s wall; median entry 107 ms; the suite itself 10 s → 3.4 s.

- 2026-09-20 — Diagnostics log + Reveal log in About; web-process termination handled (tests L1–L6).

- 2026-09-20 — `web/logic.js` + Node tests J1–J9 in CI; the 3-2-1 plan (CI, fake shell, JS harness) is complete.

- 2026-09-20 — `CommandRunner` seam + `FakeShell`; FakeShellTests F1–F8 (failures, admin routing, exact command text). ADR-15.

- 2026-09-20 — `catalog.schema.json` + SchemaTests V1–V3 (MiniSchema validator in test support); README reframed for a public, source-available repo.

- 2026-09-20 — Repo public with the EULA as LICENSE; CI (swift test + universal release build) on push/PR.
- 2026-09-19 — 0.4.0 released.
- 2026-09-19 — Trash for the `decide` bucket, permanent for the rest (ADR-13; tests D1–D5).

- 2026-09-19 — Item display names, size ordering, `childLabel` (VS Code workspaces by project); tests I9–I11.

- 2026-09-19 — Command granularity: `itemsCmd`/`deleteItemCmd`; simulators per device, runtimes per runtime (tests T1–T7).

- 2026-09-19 — 0.3.1 released (cosmetics).
- 2026-09-19 — 0.3.0 released.
- 2026-09-19 — Configurable project folders (`$PROJECTS`, detected defaults, picker, island under FDA notice; ADR-12; tests R1–R6).

- 2026-09-19 — Path granularity: items in Details with per-item Delete for glob/paths/children entries; Details breakdown for plain paths; Shell reader starvation fix (ADR-10, ADR-11; tests I1–I8, C9).

- 2026-09-19 — Homebrew orphans Details: list + total, on demand only (catalog; tests B1–B3 run the real command against a fake brew).
- 2026-09-19 — Time Machine snapshots → Managed by macOS (catalog only; test C8 pins it).
- 2026-09-19 — Test target (`Tests/ReclaimerTests`, 21 tests) and `_meta/` docs bootstrapped.
- 2026-09-19 — 0.2.0 released: themes, threshold slider, coloured meter, About panel, de-duplicated totals.
- 2026-09-19 — 0.1.0: first notarized build; universal binary; notarize script hardened.
