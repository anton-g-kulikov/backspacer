# Project Task List

Temporal: active work, queued tasks, roadmap. Status lives here and nowhere else.

## Active

_(none)_

## Queued

- **JS test harness for `web/index.html`.** Move the pure functions
  (`fmt`, threshold/visibility, nesting/own-size, meter segmentation,
  `deletable`) into `web/logic.js` so `node` can test them; page keeps
  loading them via `<script src>`. Document cases in
  `Tests/test-documentation.md` first.
- **Fake shell for `Bridge` ops.** Inject a `Shell`-like runner so `size`,
  `delete` and glob resolution can be tested without touching the disk.
- **CI.** `swift test` + `swift build -c release` on push (GitHub Actions,
  macOS runner).

## Roadmap (from the 0.1.0 README)

- "Explain" panel per entry with the full reasoning from the catalog notes.
- Simulator runtime deletion from the UI (`xcrun simctl runtime delete <id>`),
  once the info output is parsed into a picker.
- Per-project view for `~/Projects` with last-touched dates.
- Optional launch-at-login menu-bar mode that warns below a free-space threshold.
- Hold-to-confirm on the dialog's Delete button (a second gate, if wanted after ADR-5).

## Done

- 2026-09-19 — Test target (`Tests/ReclaimerTests`, 21 tests) and `_meta/` docs bootstrapped.
- 2026-09-19 — 0.2.0 released: themes, threshold slider, coloured meter, About panel, de-duplicated totals.
- 2026-09-19 — 0.1.0: first notarized build; universal binary; notarize script hardened.
