# Multi-platform design — Linux and Windows

Owner of the design for the second host decided in ADR-22. Status: **designed,
not scheduled.** Nothing here is built; the point of writing it now is that the
catalog and site work done in the meantime stays compatible with it. Read
`api-design.md` first: the bridge contract is the thing both hosts implement.

## The shape

```
web/            one page, one logic module, one test suite — shared, unchanged
catalog.json    one catalog, platform-aware (below) — shared
Sources/        the macOS host (Swift, AppKit, WKWebView, Sparkle)   ← exists
host-tauri/     the Linux + Windows host (Rust, Tauri 2)              ← this design
Tests/web/      page tests + a bridge conformance suite both hosts run
```

The Mac app is not touched by the port. The Tauri host is a second
implementation of the 25 ops in `api-design.md`; it embeds the same `web/`
directory and the same `catalog.json` at build time. Anything the page needs
that differs per OS goes through the bridge, never through user-agent sniffing
in the page.

## Transport

The page talks to the host through one function and one callback:
`bridge.call(op, args)` → `{id, op, args}` out, `window.__backspacerReply(id,
ok, payload)` back. On macOS the carrier is
`webkit.messageHandlers.backspacer.postMessage`. In Tauri the carrier is
`window.__TAURI__.core.invoke('op', {id, op, args})`; the host answers by
evaluating `__backspacerReply` in the web view exactly as Swift does. `boot.js`
picks the carrier by feature detection (`webkit.messageHandlers` → macOS,
`__TAURI__` → Tauri, neither → the mock bridge). That is the only page change
the port needs.

Reply shapes, error shape (`ok=false, {error}`), integer ids and out-of-order
replies stay as documented. Ops that are macOS-only by nature answer with the
same shape and a no-op or a documented value (below), so the page needs no
platform branches for them.

## The catalog becomes platform-aware (precondition, done before any host)

Schema additions, all optional so the current catalog stays valid:

| field | meaning |
|---|---|
| `platforms: ["macos","linux","windows"]` | which hosts show the entry; absent = macOS only (the current meaning) |
| `path` / `paths` / `glob.root` may use variables | `$HOME`, `$XDG_CACHE_HOME`, `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$LOCALAPPDATA`, `$APPDATA`, `$TEMP`, `$PROJECTS`; `~` stays as today |
| `os: { linux: {path…}, windows: {path…} }` | per-OS overrides for the location fields when the tool lives somewhere else (VS Code: `~/Library/Application Support/Code` vs `~/.config/Code` vs `%APPDATA%\Code`) |
| commands (`sizeCmd`, `itemsCmd`, …) | per-OS under `os.<platform>`; an entry with a command and no override for a platform is hidden there |

The host resolves variables for its OS; an entry whose resolved path is empty
is not shown. `platforms` defaults to `["macos"]` so the 16 Xcode/simulator/
system entries need no edit. Expected outcome on the current catalog: ~33
entries portable as they are (dot-folders, `$PROJECTS`), ~23 with an `os`
block, ~16 macOS-only, a handful of Linux/Windows-only additions (apt/dnf
caches, journal logs, the Windows Update cache, `%TEMP%`, WSL distributions).

Tests: `SchemaTests` and `CatalogTests` accept the new fields; the safety-gate
test (S7) resolves every entry for every platform it lists and runs that
platform's gate over it. The macOS app ignores `os.linux`/`os.windows` and
`platforms`, so this lands with no visible change.

## What each op needs on Linux and Windows

| op | Linux | Windows | note |
|---|---|---|---|
| `catalog` | same | same | |
| `disk` | `statvfs` on `$HOME` | `GetDiskFreeSpaceEx` on the home drive | "free" = free to the user, as today |
| `fdaStatus` / `openFDA` | `{granted: true}` / no-op | `{granted: true}` / no-op | no TCC; page hides the banner when granted |
| `size` | native walk (`walkdir` + `st_blocks`), one filesystem, symlinks not followed | native walk with allocated size; junctions and reparse points not followed | **no `du`** — PowerShell is far too slow for `node_modules` on NTFS; one walker for both |
| `info` | same breakdown from the walker; `infoCmd` only if `os.linux.infoCmd` | same | |
| `delete` | freedesktop Trash for `decide` (the `trash` crate), `remove_dir_all` otherwise; admin via `pkexec` | Recycle Bin (`IFileOperation`) for `decide`; admin via a UAC-elevated helper invocation | same disposal rule as ADR-13 |
| `reveal` | `xdg-open` on the parent, or the file manager's D-Bus `ShowItems` | `explorer /select,` | |
| `open` (Terminal) | `$TERMINAL`, else the desktop's default via `xdg-terminal-exec` | Windows Terminal if present, else `cmd` | same selector rules (ADR-10) |
| `appInfo` | from the Tauri config | same | |
| `prefGet` / `prefSet` | a JSON file under `$XDG_CONFIG_HOME/backspacer` | under `%APPDATA%\Backspacer` | same key allow-list |
| `projectRoots` / `addProjectRoot` / `removeProjectRoot` | candidates `~/Projects ~/code ~/src ~/dev ~/work ~/repos ~/git`; Tauri's folder dialog | plus `%USERPROFILE%\source\repos`; folder dialog | inside home, never the config dir |
| `log` / `logPath` / `revealLog` | `$XDG_STATE_HOME/backspacer/backspacer.log` | `%LOCALAPPDATA%\Backspacer\Logs\` | same rotation |
| `scanHints` | same, in the prefs file | same | |
| `contextTarget` | same | same | Tauri's menu API for the trimmed menu |
| `checkUpdate` | Tauri updater plugin | same | see Updates |
| `dragWindow` | `window.startDragging()` | same | |
| `__setTheme` (host → page) | from the app menu | same | |

## The safety gate, per OS

Not a translation: each OS gets its own `isSafeToDelete` with the same idea —
refuse the home folder, its top-level visible folders, the user-data roots and
anything outside the allowed roots, at any depth, after resolving links, with
case folded where the filesystem folds it.

- **Linux**: allowed roots `$HOME/` and `/var/cache/`, `/var/log/journal/`
  for the few admin entries; refuse `$HOME/.ssh`, `.gnupg`, `.config`
  itself, `Documents`, `Desktop`, `Pictures`, `Videos`, `Music`, mounted
  cloud folders; resolve symlinks and hard-link counts before `rm`.
- **Windows**: allowed roots the user profile and `%LOCALAPPDATA%`; refuse
  `Documents`, `Desktop`, `Pictures`, `Videos`, `Music`, `OneDrive*`,
  `.ssh`, `AppData\Roaming` itself; compare case-insensitively; refuse
  junctions and reparse points outright (never follow, never delete through
  one); drive letters normalised.

Both gates run over every catalog path for their platform in the test suite,
as S7 does on macOS today.

## Updates

Tauri's updater plugin plays Sparkle's role: a signed manifest per platform
(minisign keys, separate from the Sparkle EdDSA key), published as release
assets by `release.yml` and mirrored to the site by `pages.yml` the way the
appcast is. Same policy as ADR-21: download automatically, ask before
installing. Linux AppImage updates in place; `.deb` users update through apt
if a repository is ever published, otherwise they are told a new version exists.

## Packaging and distribution

| | Linux | Windows |
|---|---|---|
| bundle | AppImage (updater-capable) and `.deb`; **no Flatpak/Snap** — their sandboxes forbid deleting arbitrary folders, the same reason the Mac app has no App Sandbox | NSIS installer, x64 and arm64; **no Microsoft Store** for the same reason |
| signing | none required; SHA-256 sums in the release notes, SLSA provenance as today | a code-signing certificate (OV or EV); expect SmartScreen warnings for weeks after a new signer, as LensSense recorded |
| channels | GitHub release, the site, later a Homebrew formula on Linux | GitHub release, the site, `winget` manifest |
| CI | `ubuntu-latest` job in `release.yml`, `cargo test` + the conformance suite | `windows-latest` job, same |

## Order of work, when it is scheduled

1. **Catalog platform-awareness** (schema, tests, the `os` blocks for the
   ~23 shared tools, the new Linux/Windows entries). Ships in a normal macOS
   release with no visible change. ~3 days.
2. **Bridge conformance suite**: a Node harness that drives any host through
   the 25 ops against a fixture home and asserts the documented shapes. Run it
   against the Swift bridge first so the suite is proven before the second
   host exists. ~2 days.
3. **Tauri host, Linux**: transport, prefs, log, disk, the walker, `size`,
   `info`, `reveal`, `open`, then `delete` with the Linux gate and trash,
   then admin, then the updater. AppImage + `.deb` in `release.yml`. ~2–3
   weeks to parity.
4. **Windows**: the walker's allocated-size path, Recycle Bin, UAC, the
   Windows gate, NSIS, the certificate, `winget`. ~2–3 weeks.
5. **Site**: per-OS download buttons chosen by user agent with all three
   visible, Homebrew/`winget` commands, and the SEO pass for the new queries.

Estimates are for the two sessions working as they do now; step 1 is worth
doing early regardless, because it also tidies the current entries.

## What this design deliberately does not do

- Change the macOS app's architecture, language or dependencies.
- Put platform branches in `web/` beyond carrier detection in `boot.js`.
- Share Rust code with the Swift host; the shared artefacts are the page, the
  catalog and the tests.
- Promise feature parity for macOS-only entries; the Linux and Windows
  catalogs are smaller and honest about it.
