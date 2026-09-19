# Project Task List

Temporal: active work, queued tasks, roadmap. Status lives here and nowhere else.

## Active

_(none)_

## Queued

- **"Crashed but returned" report** (2026-09-20, after emptying the Trash and
  rescanning): no crash report existed; likely a WebKit content-process
  termination, now logged and auto-reloaded. Wait for the next occurrence
  with the log.

- **App data, round two.** Sandboxed apps' caches need Full Disk Access to
  even measure (Teams, Mail downloads, Messages attachments); Notion's
  partition holds a local DB so it stays *Your call*; Steam's and Google
  Updater's bundles are app code, not cache. Revisit with an FDA-aware entry
  flag and per-app verification.
- **AVD per-item delete** needs to remove `<name>.avd` and `<name>.ini`
  together — a two-path item; decide whether `children` grows a sibling rule
  or AVDs use `itemsCmd`.

### Review findings — 2026-09-20 (technical / security / accessibility / OSS audit)
Source: full-repo review in the "Project technical review" session. Ordered by
severity; each item names the file and the test that should pin it. Address
Critical and Severe before anything else on the roadmap; ship as 0.6.1.

#### Critical — the deletion gate has holes
- **R1 · Escape can confirm a delete.** Both confirmation flows read
  `dlg.returnValue` on `close` (`web/index.html:810`, `:836`) and never reset
  it. Per the HTML spec Escape closes the dialog without touching the return
  value, so after one real "Delete" the next dialog's Escape resolves to `ok`
  and the delete proceeds (reproduced). Fix: `dlg.returnValue = ''` before
  every `showModal()`, or resolve on the form's `submit` via `e.submitter.value`.
  Test: J-test that a cancel-path close after an `ok` close yields not-`ok`.
- **R2 · Attribute injection from folder names → deletes without a dialog.**
  `esc()` escapes only `& < >` (`web/logic.js:13`; J2 asserts quotes stay
  unescaped). Real paths are interpolated into double-quoted attributes
  (`index.html:579`, `:642`, `:793`, `:795`). Glob matches come from `find`
  over project folders, so a cloned repo containing a folder named
  `x" onmouseover="…` runs script inside the WKWebView that holds the bridge
  and can call every deletable entry with no confirmation. Fix: escape `"`
  and `'` in `esc` (fix J2), or build rows with `dataset`/`textContent`
  instead of HTML strings; add a CSP `<meta>` to `index.html`.
- **R3 · `isSafeToDelete` allows real user data.** `Bridge.swift:466` forbids
  a short list, then allows anything at depth ≥ 2 under home and every
  dot-folder: Photos Library, `~/Documents/*`, `~/Desktop/*`,
  `~/Library/Mail`, `~/Library/Keychains`, `~/Library/Mobile Documents`,
  `~/Library/CloudStorage`, `~/.ssh`, `~/.gnupg` all pass. Comparison is
  case-sensitive on a case-insensitive APFS; the staged-update root lacks a
  trailing `/` (`…/macOS Install Data-2` passes). Fix: an explicit deny-list
  by prefix, compared case-insensitively over a symlink-resolved path
  (`URL.standardizedFileURL.resolvingSymlinksInPath()`). Tests: S8 deny
  cases above, S9 case folding, S10 trailing-slash root.

#### Severe — wrong results or a frozen app
- **R4 · `user-screenshots.sizeCmd` never runs for most users.** A login zsh
  aborts the whole command on an unmatched glob (`~/Desktop/*.mov`), so the
  entry shows `?` unless both a `.mov` and a `.png` exist on the Desktop
  (reproduced). Fix: `setopt nullglob;` prefix, or `find`, or run it in
  `/bin/sh`. Test: fake-home M-test with no matches.
- **R5 · Admin deletes freeze the UI.** `runAsAdmin` hops to the main thread
  and blocks in `NSAppleScript` for the whole `rm -rf` (`Shell.swift:63`).
  A multi-GB simulator-cache delete is a beachball with no progress. Fix:
  keep only the authorization on the main thread, or show an explicit modal
  progress state while it runs.
- **R6 · Login shell mismatch.** `zsh -lc` reads `.zprofile`, not `.zshrc`,
  and ignores fish/bash users. Anyone who sets PATH in `.zshrc` gets
  `brew: command not found`. Fix: run `$SHELL -lc`, or resolve tools from
  known prefixes (`/opt/homebrew/bin`, `/usr/local/bin`) before falling back.
- **R7 · Root is one catalog edit away.** `runCatalogCommand(admin:)`
  (`Bridge.swift:353`, `:381`) would run any future `sudo` + `deleteCmd` /
  `deleteItemCmd` entry as root with a PATH-resolved tool. Fix: CatalogTests
  invariant that no entry combines `sudo` with a command; have `runAsAdmin`
  accept only paths and build `rm -rf` itself.
- **R8 · Timeouts leave orphans.** On timeout `Shell.run` terminates the
  shell, not the process group; `du`/`rm` keep running. Fix: start each
  command in its own process group and `killpg` on timeout.
- **R9 · Symlinks are never checked.** `remove()` and `children: true`
  items accept a symlinked directory (`fileExists(isDirectory:)` follows
  links). Harmless today (no trailing slash → `rm -rf` removes the link),
  dangerous the day one is added. Fix: `lstat` every target and refuse
  `S_IFLNK` before `rm`/trash. Tests: S11 symlinked child, S12 symlinked
  `glob.then` target.

#### Moderate — accessibility (WCAG 2.2 AA, VoiceOver)
- **R10 · Bucket headers are click-only `<div>`s** (`index.html:147`,
  `:762`): not focusable, no `aria-expanded`; Keep/Managed start collapsed
  so keyboard users can never open them. Fix: `<button aria-expanded
  aria-controls>` inside the `<h2>`.
- **R11 · No accessible names**: row checkboxes (`:638`) read "unchecked
  checkbox"; bucket "all" (`:627`) reads "all"; the `×` root chip (`:579`)
  has only `title`. Fix: `aria-labelledby`/`aria-label`.
- **R12 · Slider announces the raw index** (`:384`): "3", not "100 MB". Fix:
  `aria-valuetext = fmt(minBytes())` in `setThreshold` + `aria-label`.
- **R13 · No live region**: scan start/end, delete outcomes and `#sum`
  (`:710`) are silent. Fix: visually-hidden `aria-live="polite"` region;
  `#log` → `role="log"`; don't `disabled` the focused Scan button (`:680`).
- **R14 · Contrast**: `--faint` ≈ 1.9:1, `--muted` ≈ 3.6:1 (Glass);
  Terminal `--faint` ≈ 2.5:1. Fix: raise alphas (≥ .55 / ≥ .75) and add
  `@media (prefers-contrast: more)`.
- **R15 · No `prefers-reduced-motion`**: infinite caret/pending blink
  (`:226`, `:306`), 250 ms verb ticker, scale transforms. Fix: the standard
  reduce-motion override; freeze the ticker to "Scanning…".
- **R16 · Disk meter is colour-only** (`:390`, `:689`): give it `role="img"`
  + a summarising `aria-label` rebuilt in `updateMeter`.
- **R17 · Disclosure state invisible**: Details buttons, Log/About tabs,
  theme segment signal state only by class. Fix: `aria-expanded` /
  `aria-pressed`. Also: `:focus-visible` outline, dialog `aria-labelledby`
  /`aria-describedby`, 10 px badges → ≥ 11 px, h3→h4 skip in About,
  `user-select: none` blocks copying paths.

#### Hygiene — repo, release, open source
- **R18 · `scripts/mac-storage-review.sh`** is a personal script ("Anton's
  MacBook Air", "paste back into the chat"). Move to `_meta/` or delete.
- **R19 · README has no screenshot**; `assets/preview-512.png` is unused.
- **R20 · `isInspectable` is on in release** (`AppDelegate.swift:37`). Gate
  behind `DEBUG` or a defaults key.
- **R21 · `cache-logs` is "safe, no cost"** but deletes crash reports and the
  app's own diagnostics log mid-session. Reconsider bucket or exclude
  `Reclaimer/` and `DiagnosticReports/`.
- **R22 · CI hardening**: add `permissions: contents: read`; SHA-pin actions;
  on tags run `build-app.sh` ad-hoc + `codesign --verify --strict` +
  `plutil -lint`; add `dependabot.yml` for actions; the hardcoded
  `Xcode_16.4` fallback is brittle.
- **R23 · Swift 6 language mode** + strict concurrency; drop `@unchecked
  Sendable` on `Diagnostics`. Add SwiftLint/SwiftFormat + `.editorconfig`.
- **R24 · `codesign --deep`** is discouraged by Apple; harmless without
  nested code, wrong once Sparkle is added.
- **R25 · Standard menus**: Help, Edit ▸ Undo/Cut/Paste, Window ▸ Zoom /
  Bring All to Front; `CFBundleInfoDictionaryVersion` in Info.plist.
- **R26 · OSS files**: CODE_OF_CONDUCT.md, `.github/FUNDING.yml`; GitHub
  topics are empty and the license is detected as "Other" (custom preamble in
  LICENSE — consider a pure PolyForm text + NOTICE, and an SPDX line).
- **R27 · Test gaps**: S7 covers only static `path`/`paths` — extend to glob
  roots/`then`, `children` items; `Shell.runAsAdmin` escaping; `Shell.q`
  with newline; catalog `note` free of HTML; every glob root under an
  allowed prefix.

#### Not yet adopted (SOTA)
- In-app updates (Sparkle 2, EdDSA + appcast) or a "Check for updates"
  against the GitHub releases API.
- Homebrew cask.
- Tag-triggered release workflow: temp keychain + Developer ID, notarytool,
  DMG upload, SLSA provenance (`actions/attest-build-provenance`), SHA-256
  sums in release notes.
- Unified logging (`os.Logger`) alongside the file log.
- axe-core over the page in the Node suite; manual VoiceOver pass on the
  release checklist.
- Localization scaffolding.

## Roadmap (from the 0.1.0 README)

- "Explain" panel per entry with the full reasoning from the catalog notes.
- Per-project view for `~/Projects` with last-touched dates.
- Optional launch-at-login menu-bar mode that warns below a free-space threshold.
- Hold-to-confirm on the dialog's Delete button (a second gate, if wanted after ADR-5).

## Done

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
