# Project Task List

Temporal: active work, queued tasks, roadmap. Status lives here and nowhere else.

## Active

_(none)_

## Queued

- **`catalog.schema.json`.** `catalog.json` references it but it doesn't
  exist. Write it (entry fields, bucket enum, `children` ⇒ single `path`,
  `itemsCmd` ⇔ `deleteItemCmd` with `{key}`), and add a test that validates
  the catalog against it so edits from outside are caught.

- **AVD per-item delete** needs to remove `<name>.avd` and `<name>.ini`
  together — a two-path item; decide whether `children` grows a sibling rule
  or AVDs use `itemsCmd`.

- **JS test harness for `web/index.html`.** Move the pure functions
  (`fmt`, threshold/visibility, nesting/own-size, meter segmentation,
  `deletable`) into `web/logic.js` so `node` can test them; page keeps
  loading them via `<script src>`. Document cases in
  `Tests/test-documentation.md` first.
- **Fake shell for `Bridge` ops.** Inject a `Shell`-like runner so `size`,
  `delete` and glob resolution can be tested without touching the disk.

## Roadmap (from the 0.1.0 README)

- "Explain" panel per entry with the full reasoning from the catalog notes.
- Simulator runtime deletion from the UI (`xcrun simctl runtime delete <id>`),
  once the info output is parsed into a picker.
- Per-project view for `~/Projects` with last-touched dates.
- Optional launch-at-login menu-bar mode that warns below a free-space threshold.
- Hold-to-confirm on the dialog's Delete button (a second gate, if wanted after ADR-5).

## Done

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
