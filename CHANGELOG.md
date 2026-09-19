# Changelog

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
