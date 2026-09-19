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
| `size` | `{id}` | `{bytes: int\|null, paths: [string], items?: [{path, bytes}]}` | `null` when `sizeCmd` output is unparseable or the entry has no source. `items` only for granular entries (`glob`, `paths`, `children: true`): one per match / listed path / subfolder |
| `info` | `{id}` | `{text}` | `infoCmd` output, capped at 20 000 chars; without an `infoCmd`, a size breakdown of the first path's contents, largest first (40 lines) |
| `delete` | `{id, item?}` | `{ok, freedBytes}` | refuses non-deletable entries and unsafe paths; admin entries prompt via macOS. With `item`: deletes that one path of a granular entry — `item` is a selector, accepted only if it is in the entry's freshly resolved item set, and never for entries with a `deleteCmd` |
| `reveal` | `{id}` | `{ok}` | Finder-selects the first resolved path |
| `appInfo` | — | `{version, build}` | `CFBundleShortVersionString`, `CFBundleVersion` |
| `prefGet` | `{key}` | `{value: string\|null}` | keys: `theme`, `minSize` |
| `prefSet` | `{key, value}` | `{ok}` | value ≤ 32 chars |

## Host → page calls

| call | when |
|---|---|
| `window.__reclaimerReply(id, ok, payload)` | every reply |
| `window.__setTheme("glass"\|"terminal")` | View menu |

## Mock bridge

When `webkit.messageHandlers.reclaimer` is absent (plain browser), `mockBridge()`
answers every op with random sizes, a fixed 245 GB disk, `localStorage`-backed
prefs, and a `dev (browser)` version. `?theme=…` on the URL selects a theme.
