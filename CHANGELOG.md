# Changelog

## Unreleased
- Info everywhere: every path-based entry has an Info button. Multi-path entries (node_modules, Pods, build output in ~/Projects; VS Code caches) list each match with its size and its own Delete. New `children: true` entries do the same for subfolders: iOS DeviceSupport (no longer "manual"), Xcode archives, DerivedData, Android system images. Plain folders show a breakdown of what's inside.
- Fixed: a command's output could be lost (reported empty after its timeout) when several ran at once — pipe readers are now on dedicated threads.
- Homebrew orphaned dependencies: Info now lists the formulae with their total Cellar size, or says "No orphaned dependencies." The check runs only when Info is pressed, never during a scan.
- Time Machine local snapshots moved from Safe to delete to Managed by macOS (read-only, Info kept). macOS purges them itself and the free-space figure already counts them, so thinning gained nothing visible. The note gives the manual `tmutil` command for the rare case a tool needs non-purgeable space.

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
