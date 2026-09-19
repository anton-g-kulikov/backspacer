# API Design — the JS ⇄ Swift bridge

The only interface in the system. JS calls `bridge.call(op, args)`; the host
replies `window.__reclaimerReply(id, ok, payload)`. Transport is
`webkit.messageHandlers.reclaimer.postMessage({id, op, args})`.

## Contract rules

1. **No paths cross the bridge from JS.** Disk ops take a catalog `id`; the
   host resolves it from its own copy of `catalog.json`.
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
| `size` | `{id}` | `{bytes: int\|null, paths: [string]}` | `null` when `sizeCmd` output is unparseable or the entry has no source |
| `info` | `{id}` | `{text}` | `infoCmd` output, capped at 20 000 chars |
| `delete` | `{id}` | `{ok, freedBytes}` | refuses non-deletable entries and unsafe paths; admin entries prompt via macOS |
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
