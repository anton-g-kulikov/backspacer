# Changelog

## Unreleased
- Scans are faster: measurement commands no longer start a login shell (which cost ~0.8 s each); small entries now measure in milliseconds. What remains is real disk work (node_modules across many projects is the biggest).
- Diagnostics log at `~/Library/Logs/Reclaimer/Reclaimer.log` (About → Reveal log): scans, deletes and the commands run, failures, page errors, WebKit content-process restarts. Attach it to a bug report.
- If WebKit's content process dies, the page reloads instead of going blank.
- Internal: the page's pure logic moved to `web/logic.js` and is tested under Node; the bridge's shell is injectable and tested against a scripted fake.
- `catalog.schema.json`: the catalog is described by a JSON Schema — editors validate as you type, and the test suite validates the shipped catalog and checks the schema rejects the mistakes that matter.
- Source published under the PolyForm Noncommercial License 1.0.0 (free for noncommercial use; the name and icon stay reserved); CI on every push.

## 0.4.0 — 2026-09-19
- Your-call items (archives, DeviceSupport, app data, workspaces…) now go to the Trash instead of being removed outright; the dialog reads "Move to Trash" and reminds you to empty it to free the space. Caches and build output are still removed for good.
- Details lists are sorted largest first; project-folder matches are named relative to their project (`drtalk/ios/build`, not `build`).
- VS Code workspace storage: Details names each workspace by its project (`~/Projects/reclaimer`) instead of a hash, with a Delete per workspace.
- Simulators and runtimes, one at a time: Details on "Simulator device contents" lists every simulator with its data size and an Erase-style Delete per device; "Simulator runtimes" is no longer manual — Details lists each runtime (~8 GB) with its own Delete.

## 0.3.1 — 2026-09-19
- Traffic lights sit on the page: transparent title bar, content under it.
- Header, cards and footer share the same edges whatever the scrollbar setting; 10 px breathing room above and below the floating bars (Glass).
- Bucket totals in the bucket's colour: tinted capsule (Glass), coloured text (Terminal).
- Terminal: no scanline overlay (it striped the glyphs); `[ details ] [ reveal ]` grouped with `[ delete ]` set apart; `[ ]` checkboxes keep their width.
- Glass: Details and Reveal buttons the same size.

## 0.3.0 — 2026-09-19
- About panel: tagline, a short note on what Reclaimer is and isn't, version with build number on hover.
- The Info button is now Details.
- Project folders are no longer hardcoded to `~/Projects`. Reclaimer detects common folder names (`~/Projects`, `~/Developer`, `~/code`, `~/src`, …) and shows them in a "Project folders" island; **Add folder…** opens the macOS picker for any other location, `×` removes one. Build-output entries (node_modules, Pods, Next.js, Android/iOS/.NET output) search every listed folder.
- Details everywhere: every path-based entry has a Details button. Multi-path entries (node_modules, Pods, build output in ~/Projects; VS Code caches) list each match with its size and its own Delete. New `children: true` entries do the same for subfolders: iOS DeviceSupport (no longer "manual"), Xcode archives, DerivedData, Android system images. Plain folders show a breakdown of what's inside.
- Fixed: a command's output could be lost (reported empty after its timeout) when several ran at once — pipe readers are now on dedicated threads.
- Homebrew orphaned dependencies: Details now lists the formulae with their total Cellar size, or says "No orphaned dependencies." The check runs only when Details is pressed, never during a scan.
- Time Machine local snapshots moved from Safe to delete to Managed by macOS (read-only, Details kept). macOS purges them itself and the free-space figure already counts them, so thinning gained nothing visible. The note gives the manual `tmutil` command for the rare case a tool needs non-purgeable space.

## 0.2.0 — 2026-09-19
- Two looks: Glass (default, follows light/dark) and Terminal; switch in the header or View → ⌘1/⌘2. Remembered between launches.
- "Show ≥" size threshold slider (10 MB – 10 GB, default 100 MB). Smaller items are hidden and can't be deleted.
- Disk meter colour-coded by bucket, reclaimable space next to free.
- Keep and Managed-by-macOS start collapsed; every bucket header toggles.
- Nested caches (Homebrew, yarn, CocoaPods, pip inside `~/Library/Caches`) counted once.
- About panel: version, license, support and Buy-me-a-coffee links.
- Removed: the "arm deletion" switch (the confirmation dialog is the gate) and the header's reclaimable total.
- Fixed: "Delete selected" clipped in the footer.

## 0.1.0 — 2026-09-19
- First notarized release. Universal binary, hardened runtime, DMG with Applications shortcut.
