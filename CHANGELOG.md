# Changelog

## Unreleased
- Internal: CI steps fail when the command in a pipe fails (`pipefail`); the folder picker compiles under Xcode 16's Swift 6.0 compiler, which is now the verified toolchain floor.

## 0.7.0 — 2026-09-20
- Internal: Swift 6 language mode with strict concurrency; signing without `--deep`; the origin audit script moved under `_meta/`.
- Window menu gets Zoom and Bring All to Front; a Help menu links to GitHub, the issue tracker and the diagnostics log.
- App data behind Full Disk Access (Mail attachment downloads, Microsoft Teams cache, Messages attachments, plus Safari, Telegram, iPhone backups, UTM, Docker) is marked with a "disk access" badge and shows "needs access" instead of quietly disappearing when the permission isn't granted.
- Android virtual devices are listed per device in Details; deleting one removes its `.ini` too, so Device Manager doesn't show a broken entry.

## 0.6.3 — 2026-09-20 (accessibility)
- Accessibility: secondary text (notes, paths, group labels) has more contrast in both themes, with a further boost when macOS is set to increase contrast; animations stop under Reduce Motion. Bucket headers are keyboard-operable buttons that announce their state; every checkbox, the size slider, the disk meter, the Details buttons, tabs and theme switch have proper names and states for VoiceOver; scan and delete outcomes are announced; a visible focus ring; paths can be selected and copied.

## 0.6.2 — 2026-09-20 (security and robustness)
- The Web Inspector is off in release builds (`defaults write com.antonkulikov.reclaimer WebInspector -bool YES` turns it on).
- `~/Library/Logs` is listed per app in Details; deleting it no longer removes crash reports or Reclaimer's own diagnostics log.
- Fixed: a command that hits its time limit is now stopped together with everything it started; before, the shell was stopped but a long `du` or `rm` could keep running in the background.
- Fixed: Homebrew, .NET and other tool-based entries work even when your shell profile doesn't put those tools on the login PATH (`.zshrc`-only setups, bash, fish).
- Fixed: deleting an admin-only item (simulator caches, staged updates) no longer freezes the app for the duration of the delete. The password prompt is unchanged.
- Fixed: "Screenshots and screen recordings" showed `?` unless the Desktop happened to hold both a .mov and a .png; it now measures `~/Screenshots` plus Desktop recordings and screenshots on every Mac (2.2 GB on the reference Mac that were previously invisible).
- Hardened: symbolic links are never deleted or trashed, whatever they point at.
- Hardened: admin (password-prompt) entries can only ever remove paths the app checked itself — a catalog entry can no longer combine admin with a custom command.
- Hardened: the deletion gate now refuses your data at any depth — Documents, Desktop, Pictures, Photos libraries, Mail, Messages, Keychains, iCloud Drive, cloud-storage folders, Safari, `.ssh`, `.gnupg` — resolves symlinks first and compares names case-insensitively. Project folders you added yourself are the one exception, for what the globs find inside them.
- Hardened: a folder whose name contains quotes or HTML can no longer affect the page (names are fully escaped, and the page forbids inline script via a Content-Security-Policy).
- Fixed: pressing Escape on a confirmation dialog right after a previous Delete could confirm instead of cancel. Every dialog now starts from a clean slate and only an explicit Delete / Move to Trash confirms.

## 0.6.1 — 2026-09-20
- Scans are faster again, without straining the machine: four entries measure at once, entries with many folders are measured two at a time, and the slow ones start first (the app remembers how long each took). Full scan on the reference Mac: 27 s → 16 s.

## 0.6.0 — 2026-09-20
- App data, revamped. One "App caches (Electron)" entry finds the web caches every Electron app keeps next to its data (Slack, Claude, VS Code, Notion, Figma, Discord, Postman…) with a Delete per app; `~/Library/Caches` and `~/.cache` list one item per app or tool. New entries: iPhone/iPad backups (per device, by name), Ollama models (per model), VS Code dictation models, SwiftUI preview data, Spotify cache, Bun / pub / Maven / conda caches, Parallels and UTM VMs (measured, deleted from their own apps). Slack's cache is no longer a "Your call" entry — it's a cache, so it's removed rather than moved to the Trash.
- Rows moved to the Trash now say "in Trash" instead of showing 0 KB.
- The confirmation dialog grows with its content (long paths wrap, no scrollbar) and, for a single item, names the entry first: "Delete from VS Code workspace storage?" rather than "Delete ~/Projects/enumerator?".

## 0.5.0 — 2026-09-20
- While scanning, the header cycles through verbs (measuring, surveying, rummaging…) in a fresh order each time.
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
