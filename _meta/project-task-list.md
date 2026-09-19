# Project Task List

Temporal: active work, queued tasks, roadmap. Status lives here and nowhere else.

## Active

_(none)_

## Queued — in order

Numbered by priority. R-numbers are the 2026-09-20 technical review's findings
(file:line and the test that pins each); un-numbered items are earlier work.
Each becomes a bounded task: failing test first, one change, docs in the owning
file, then moved to Done.

### Critical — the deletion gate has holes
### Severe — wrong results or a frozen app
6. **R4 · `user-screenshots.sizeCmd` never runs for most users.** The login
   zsh aborts on an unmatched glob (`~/Desktop/*.mov`) → `?`. Fix: `find`
   or `/bin/sh`. Test: fake home with no matches measures 0, not `?`.
7. **R5 · Admin deletes freeze the UI.** `runAsAdmin` blocks the main thread
   in `NSAppleScript` for the whole `rm -rf` (a multi-GB delete is a
   beachball). Fix: authorise on the main thread only, run the work off it,
   or show an explicit progress state.
8. **R6 · Login shell mismatch.** `zsh -lc` reads `.zprofile`, not `.zshrc`;
   fish/bash users get `brew: command not found`. Fix: `$SHELL -lc`, or
   resolve tools from known prefixes (`/opt/homebrew/bin`, `/usr/local/bin`)
   first.
9. **R8 · Timeouts leave orphans.** `Shell.run` terminates the shell, not
   the process group; `du`/`rm` keep running. Fix: own process group per
   command, `killpg` on timeout.
10. **R21 · `cache-logs` deletes crash reports and the app's own diagnostics
    log mid-session.** Reconsider the bucket or exclude `Reclaimer/` and
    `DiagnosticReports/`.
11. **R20 · `isInspectable` is on in release.** Gate behind `DEBUG` or a
    defaults key.
12. **"Crashed but returned" report** (2026-09-20): now logged and
    auto-reloaded; wait for the next occurrence with the log.

### Moderate — accessibility (WCAG 2.2 AA, VoiceOver)
13. **R10 · Bucket headers are click-only `<div>`s** — not focusable, no
    `aria-expanded`; Keep/Managed start collapsed so keyboard users can never
    open them. Fix: `<button aria-expanded aria-controls>` in the `<h2>`.
14. **R11 · No accessible names**: row checkboxes read "unchecked checkbox",
    bucket "all", the `×` root chip has only `title`. Fix:
    `aria-labelledby`/`aria-label`.
15. **R12 · Slider announces the raw index** ("3", not "100 MB"). Fix:
    `aria-valuetext` in `setThreshold` + `aria-label`.
16. **R13 · No live region** for scan start/end, delete outcomes, `#sum`.
    Fix: visually-hidden `aria-live="polite"`; `#log` → `role="log"`; don't
    disable the focused Scan button.
17. **R14 · Contrast**: `--faint` ≈ 1.9:1, `--muted` ≈ 3.6:1 (Glass);
    Terminal `--faint` ≈ 2.5:1. Fix: raise alphas (≥ .55 / ≥ .75), add
    `@media (prefers-contrast: more)`.
18. **R15 · No `prefers-reduced-motion`**: infinite blinks, the 250 ms
    ticker, scale transforms. Fix: the standard override; freeze the ticker
    to "Scanning…".
19. **R16 · Disk meter is colour-only.** `role="img"` + a summarising
    `aria-label` rebuilt in `updateMeter`.
20. **R17 · Disclosure state invisible**: Details, Log/About tabs, theme
    segment signal state only by class. Fix: `aria-expanded` /
    `aria-pressed`; `:focus-visible` outline; dialog `aria-labelledby` /
    `aria-describedby`; badges ≥ 11 px; About heading order; allow selecting
    paths.

### Features (earlier queue)
21. **AVD per-item delete** — `<name>.avd` + `<name>.ini` as one item;
    decide whether `children` grows a sibling rule or AVDs use `itemsCmd`.
22. **App data, round two** — sandboxed apps need Full Disk Access to even
    measure (Teams, Mail, Messages); Notion stays *Your call*; Steam/Google
    Updater bundles are app code. Needs an FDA-aware entry flag.

### Hygiene — repo, release, open source
23. **R22 · CI hardening**: `permissions: contents: read`; SHA-pin actions;
    on tags run an ad-hoc `build-app.sh` + `codesign --verify --strict` +
    `plutil -lint`; `dependabot.yml`; the `Xcode_16.4` fallback is brittle.
24. **R27 · Test gaps**: S7 only covers static `path`/`paths` — extend to
    glob roots/`then` and `children` items; `Shell.runAsAdmin` escaping;
    `Shell.q` with newline; catalog `note` free of HTML; every glob root
    under an allowed prefix.
25. **R26 · OSS files**: CODE_OF_CONDUCT.md, `.github/FUNDING.yml`, GitHub
    topics; license detected as "Other" (custom preamble) — consider pure
    PolyForm text + NOTICE and an SPDX line.
26. **R19 · README has no screenshot**; `assets/preview-512.png` is unused.
27. **R18 · `scripts/mac-storage-review.sh`** is a personal script; move to
    `_meta/` or delete.
28. **R25 · Standard menus**: Help, Edit ▸ Undo/Cut/Paste, Window ▸ Zoom /
    Bring All to Front; `CFBundleInfoDictionaryVersion`.
29. **R24 · `codesign --deep`** is discouraged by Apple; wrong once nested
    code (Sparkle) exists.
30. **R23 · Swift 6 language mode** + strict concurrency; drop `@unchecked
    Sendable` on `Diagnostics`; SwiftLint/SwiftFormat, `.editorconfig`.

## Roadmap (ideas, not grounded)

From the 2026-09-20 review: in-app updates (Sparkle 2 or a "Check for updates"
against the GitHub releases API); Homebrew cask; a tag-triggered release
workflow (temp keychain, notarytool, DMG upload, SLSA provenance, SHA-256 in
the notes); `os.Logger` alongside the file log; axe-core in the Node suite and
a VoiceOver pass on the release checklist; localization scaffolding.

From the 0.1.0 README:

- "Explain" panel per entry with the full reasoning from the catalog notes.
- Per-project view for `~/Projects` with last-touched dates.
- Optional launch-at-login menu-bar mode that warns below a free-space threshold.
- Hold-to-confirm on the dialog's Delete button (a second gate, if wanted after ADR-5).

## Done

- 2026-09-20 — R9: `remove()` lstat-refuses symlinks for whole entries, children and `glob.then` targets (I14).
- 2026-09-20 — R7: `sudo` + command forbidden by schema (V2), catalog (C11) and bridge (F11); `runCatalogCommand` can't run as admin.
- 2026-09-20 — R3: user-data deny-list at any depth, case-folded, symlink-resolved, project-folder exemption (S8–S11).
- 2026-09-20 — R2: `esc` escapes quotes; CSP `script-src 'self'` with inline scripts moved to boot.js/app.js (J2, J15; ADR-17; verified in browser and app).
- 2026-09-20 — R1: Escape could confirm a delete; `confirmDialog` resets `returnValue` and both flows use it (J14, verified against the real dialog).
- 2026-09-20 — 0.6.1 released.
- 2026-09-20 — Scan speed round two: 4 workers, 2-way `du` for multi-path entries, heavy-first order from remembered durations; 27 s → 16 s wall, ≤ 8 `du` processes (tests F9, F10, L7, J13).

- 2026-09-20 — 0.6.0 released.
- 2026-09-20 — App data revamp: Electron-cache glob, per-app items for `~/Library/Caches` and `~/.cache`, iOS backups by device (plist `childLabel`), Ollama per model, dictation models, previews, Spotify, Bun/pub/Maven/conda, VMs; "in Trash" row state. Tests C10, I12, I13, T8, J12.

- 2026-09-20 — 0.5.0 released.
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
