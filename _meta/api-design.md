# API Design — the JS ⇄ Swift bridge

The only interface in the system. JS calls `bridge.call(op, args)`; the host
replies `window.__backspacerReply(id, ok, payload)`. Transport is
`webkit.messageHandlers.backspacer.postMessage({id, op, args})`.

## Contract rules

1. **No paths cross the bridge from JS as instructions.** Disk ops take a
   catalog `id`; the host resolves it from its own copy of `catalog.json`. The
   one path-shaped argument, `delete.item`, is a selector that must match a
   path the host itself just resolved (ADR-10).
2. Every op is request/response with an integer `id`; replies may arrive out
   of order.
3. Errors come back as `ok=false, {error: string}` and surface as a rejected
   promise.
4. Adding an op means: handler in `Bridge.handle`, a mock case in
   `mockBridge()`, a row here, and a test where the op has logic.

## Ops

| op | args | reply | notes |
|---|---|---|---|
| `catalog` | — | raw `catalog.json` | passed through verbatim (`RawJSON`) |
| `disk` | — | `{size, free, used}` bytes | `free` includes purgeable space, matching Finder |
| `fdaStatus` | — | `{granted: bool}` | probes `~/Library/Safari` |
| `openFDA` | — | `{ok}` | opens the Full Disk Access pane |
| `size` | `{id}` | `{bytes: int\|null, paths: [string], items?: [{path, bytes, display} \| {key, label, bytes}], fda?: true}` | `null` when `sizeCmd` output is unparseable, the entry has no source, or (`fda: true` in the reply) the entry needs Full Disk Access that isn't granted. `items` only for granular entries, largest first: path items (`glob` / `paths` / `children: true`) carry `display` — relative to the project folder for glob matches, the `childLabel` value or folder name for children, `~`-abbreviated otherwise; keyed items (`itemsCmd`) carry `label` |
| `info` | `{id}` | `{text}` | `infoCmd` output, capped at 20 000 chars; without an `infoCmd`, a size breakdown of the first path's contents, largest first (40 lines) |
| `delete` | `{id, item?}` | `{ok, freedBytes, trashed?: true}` | refuses non-deletable entries and unsafe paths; admin entries prompt via macOS. With `item`: one item of a granular entry — a path (then `rm -rf`, never for entries with a `deleteCmd`) or a key (then `deleteItemCmd` with `{key}` replaced by the shell-quoted key). Either way `item` is a selector, accepted only if it is in a fresh resolve / fresh `itemsCmd` run |
| `reveal` | `{id}` | `{ok}` | Finder-selects the first resolved path |
| `appInfo` | — | `{version, build}` | `CFBundleShortVersionString`, `CFBundleVersion` |
| `prefGet` | `{key}` | `{value: string\|null}` | keys: `theme`, `minSize`, `autoUpdateCheck` (the last one also flips Sparkle's `automaticallyChecksForUpdates`), `projectView` (`tool`/`project`) |
| `prefSet` | `{key, value}` | `{ok}` | value ≤ 32 chars |
| `projectRoots` | — | `{roots: [{path, display}]}` | folders `$PROJECTS` globs search; `display` abbreviates home as `~` |
| `addProjectRoot` | — | `{roots}` | opens the macOS folder picker; the chosen folder must be inside home and not under `~/Library`; de-duplicated; persisted (`ui.projectRoots`) |
| `removeProjectRoot` | `{path}` | `{roots}` | `path` must be a listed root (selector, like `delete.item`) |
| `log` | `{level, message}` | `{ok}` | appends a `page:` line to the diagnostics file; unknown level → `info`; message capped at 2000 chars |
| `logPath` | — | `{path}` | where the diagnostics file lives |
| `scanHints` | — | `{durations: {id: ms}}` | how long each entry's last `size` took; the page starts the slow ones first |
| `revealLog` | — | `{path}` | selects the diagnostics file in Finder |
| `contextTarget` | `{id, item?}` | `{ok}` | sent by the page on right-click over a row (entry id) or a Details item (its selector); the bridge notes it on the main thread before queuing, so the native context menu that follows can offer an action for it; quiet |
| `open` | `{id, item?, with}` | `{path}` | the context menu's path action: opens the entry's first path, or one of its current Details items (any other selector is refused), with `with: "terminal"` (the only app the page may name — Finder is the row's Reveal) |
| `checkUpdate` | — | `{ok}` or `{skipped: unconfigured}` | asks Sparkle to check now (it shows its own window); a build without a feed says `unconfigured`. Sparkle → page goes the other way: `window.__updateFound(version)` when a newer version has been found and downloaded |
| `projects` | — | `{projects: [{path, display, touched, source}]}` | every direct folder of every project root (files and hidden folders skipped), with when it was last touched — `touched` is a unix time from `git log -1` where a `.git` exists (`source: "git"`), else the newest modification among its top-level entries that are not build output (`"mtime"`), else null. The by-project view regroups the `$PROJECTS` entries' items by these paths |
| `revealProject` | `{path}` | `{ok}` | reveals a project folder in Finder; the path must be a member of a fresh `projects` listing |
| `dragWindow` | — | `{ok}` | the page's header is a window drag region: sent on mouse-down there, the bridge calls `NSWindow.performDrag(with:)` on the event still in flight (WKWebView has no drag regions of its own); quiet, no-op without a window |

## Host → page calls

| call | when |
|---|---|
| `window.__backspacerReply(id, ok, payload)` | every reply |
| `window.__setTheme("glass"\|"terminal")` | View menu |

## Mock bridge

When `webkit.messageHandlers.backspacer` is absent (plain browser), `mockBridge()`
answers every op with random sizes, a fixed 245 GB disk, `localStorage`-backed
prefs, and a `dev (browser)` version. `?theme=…` on the URL selects a theme.
