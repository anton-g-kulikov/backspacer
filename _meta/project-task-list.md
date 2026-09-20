# Project Task List

Temporal: active work, queued tasks, roadmap. Status lives here and nowhere else.

## Active

_(none)_

## Queued — in order

Numbered by priority. R-numbers are the 2026-09-20 technical review's findings
(file:line and the test that pins each); un-numbered items are earlier work.
Each becomes a bounded task: failing test first, one change, docs in the owning
file, then moved to Done.

### Next — site goes live (maintainer)
- Enable GitHub Pages on the repo with source "GitHub Actions", set the custom
  domain `backspacer.dev` and Enforce HTTPS (`gh api -X PUT
  repos/anton-g-kulikov/backspacer/pages -f cname=backspacer.dev -F
  https_enforced=true` once the first deploy has run), and verify the domain
  under account Settings → Pages (`VERIFY=<code> scripts/pages-dns.sh`).

### Critical — the deletion gate has holes
### Severe — wrong results or a frozen app
12. **"Crashed but returned" report** (2026-09-20): now logged and
    auto-reloaded; wait for the next occurrence with the log.

### Moderate — accessibility (WCAG 2.2 AA, VoiceOver)
### Features (earlier queue)
### Hygiene — repo, release, open source
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

- 2026-09-20 — Promo site: `site/index.html` (buckets and groups from the catalog, live version badge, hashed CSP, light/dark screenshots), `pages.yml` (SHA-pinned, `SITE_REQUIRED=1` gate), `scripts/site-csp.mjs`; backspacer.dev DNS via `scripts/pages-dns.sh`. Tests W1–W11. Pages must still be enabled on the repo with the custom domain — maintainer step.

- 2026-09-20 — 0.8.0 released: first release as Backspacer; CI honest again (pipefail), Xcode 16.4 toolchain floor.
- 2026-09-20 — Renamed to Backspacer (ADR-20): app, bundle id `com.antonkulikov.backspacer`, module and test target, log folder, scripts, LICENSE, docs, repository (old URL redirects); tests N1–N2, K1–K6 (K6 guards against the old name creeping back). First release under the name: 0.8.0.
- 2026-09-20 — CI honest again: `shell: bash` (pipefail) — `swift test | tail` had masked `error: fatalError` on Xcode 16.4 since R23, three hollow green runs; the folder picker's main-actor isolation made explicit for the Swift 6.0 compiler (verified on the runner via PR #2; no local Xcode 16).
- 2026-09-20 — CI package guard fixed: the v0.7.0 tag run died with `error: fatalError` (native `swift build` after a universal one, Swift 6.0 toolchain); the step now builds `UNIVERSAL=1` and runs on every push.
- 2026-09-20 — 0.7.0 released: AVD per-device delete, FDA badge and needs-access state, Window/Help menus, Swift 6, no `--deep`.
- 2026-09-20 — R23: Swift 6 language mode; Bridge handler conformance isolated in an extension, Data hand-off; Diagnostics Sendable; .editorconfig (ADR-19). Review queue complete.
- 2026-09-20 — R24: no `codesign --deep`; nested-code guard in build-app.sh; release checklist notes the inside-out rule.
- 2026-09-20 — R25: Window/Help menus completed; Edit keeps only Copy/Select All (no editable fields, so Undo/Cut/Paste would be inert); Info.plist dictionary version.
- 2026-09-20 — R18: the origin audit script moved to `_meta/origin-storage-review.sh`, header de-personalised.
- 2026-09-20 — R19: README screenshot (assets/screenshot-glass.png, captured from the app). preview-512.png is the icon preview, kept for the icon source.
- 2026-09-20 — R26: CODE_OF_CONDUCT, FUNDING.yml, GitHub topics. LICENSE preamble kept: PolyForm isn't in GitHub's detector, so a pure text would still read "Other".
- 2026-09-20 — R27: S12 (glob/children paths pass the gate), Q4 (newline in a path), C15 (plain catalog text); M6 already covers admin escaping.
- 2026-09-20 — R22: CI hardened (read-only token, SHA-pinned actions, lint steps, tag-time package check, Dependabot).
- 2026-09-20 — App data round two: `fda` flag, needs-access state, Mail downloads / Teams cache / Messages attachments (F12, C14, J16).
- 2026-09-20 — AVD per-item delete via `companion` on children entries (I16, C13).
- 2026-09-20 — 0.6.3 released: accessibility tier (R10–R17).
- 2026-09-20 — Accessibility visuals: R14 contrast (A7 computes ratios from the tokens), R15 reduced motion (A8). Accessibility tier complete.
- 2026-09-20 — Accessibility semantics: R10, R11, R12, R13, R16, R17 (A1–A6; browser accessibility tree verified).
- 2026-09-20 — 0.6.2 released: Critical (R1–R3, R7, R9) and Severe (R4–R6, R8, R20, R21) tiers.
- 2026-09-20 — R20: Web Inspector only in DEBUG or with the `WebInspector` default.
- 2026-09-20 — R21: `exclude` for children entries; `~/Library/Logs` spares DiagnosticReports and Reclaimer (I15, C12).
- 2026-09-20 — R8: posix_spawn in its own process group, clean signal mask, killpg on timeout (M9, M10).
- 2026-09-20 — R6: known tool prefixes appended to PATH for catalog commands (M8).
- 2026-09-20 — R5: admin commands run in a helper copy of the app (`--admin`), the main thread never blocks (M6, M7, M7b; ADR-18).
- 2026-09-20 — R4: screenshots entry uses `find`, never an unmatched glob (B4, B5).
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
