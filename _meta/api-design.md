# API Design — the JS ⇄ Swift bridge

The only interface in the system. JS calls `bridge.call(op, args)`; the host
replies `window.__reclaimerReply(id, ok, payload)`. Transport is
`webkit.messageHandlers.reclaimer.postMessage({id, op, args})`.

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
| `prefGet` | `{key}` | `{value: string\|null}` | keys: `theme`, `minSize` |
| `prefSet` | `{key, value}` | `{ok}` | value ≤ 32 chars |
| `projectRoots` | — | `{roots: [{path, display}]}` | folders `$PROJECTS` globs search; `display` abbreviates home as `~` |
| `addProjectRoot` | — | `{roots}` | opens the macOS folder picker; the chosen folder must be inside home and not under `~/Library`; de-duplicated; persisted (`ui.projectRoots`) |
| `removeProjectRoot` | `{path}` | `{roots}` | `path` must be a listed root (selector, like `delete.item`) |
| `log` | `{level, message}` | `{ok}` | appends a `page:` line to the diagnostics file; unknown level → `info`; message capped at 2000 chars |
| `logPath` | — | `{path}` | where the diagnostics file lives |
| `scanHints` | — | `{durations: {id: ms}}` | how long each entry's last `size` took; the page starts the slow ones first |
| `revealLog` | — | `{path}` | selects the diagnostics file in Finder |

## Host → page calls

| call | when |
|---|---|
| `window.__reclaimerReply(id, ok, payload)` | every reply |
| `window.__setTheme("glass"\|"terminal")` | View menu |

## Mock bridge

When `webkit.messageHandlers.reclaimer` is absent (plain browser), `mockBridge()`
answers every op with random sizes, a fixed 245 GB disk, `localStorage`-backed
prefs, and a `dev (browser)` version. `?theme=…` on the URL selects a theme.
