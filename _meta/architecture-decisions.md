# Architecture Decisions

Short records of choices that shape the codebase. Newest last.

## ADR-1 — HTML UI in a WKWebView, no SwiftUI/AppKit views
The UI is one HTML file that also runs in a browser with a mock bridge. Iterating
on layout and copy needs no Xcode; the Swift side stays small and rarely changes.
Cost: a bridge layer and a second language. Accepted.

## ADR-2 — The web layer never names a path
Every disk op takes a catalog id; Swift resolves paths from its own copy of
`catalog.json`. A bug or injection in JS cannot delete anything the catalog
doesn't describe. `isSafeToDelete` is a second, independent gate on the
resolved path.

## ADR-3 — No App Sandbox, hardened runtime on
The app must delete under `~/Library`, `/Library/Developer` and run `xcrun` /
`brew`, which the sandbox forbids. Developer ID distribution doesn't require
the sandbox; notarization requires the hardened runtime, which we enable with
no exception entitlements.

## ADR-4 — Admin work via `do shell script … with administrator privileges`
No privileged helper tool, no XPC, no password handling. macOS shows its own
dialog; the app never sees the password. Works under the hardened runtime.
Cost: one prompt per admin delete. Accepted.

## ADR-5 — Confirmation dialog is the single deletion gate (0.2.0)
0.1.0 had an "arm" switch that was off on every launch. It was removed because
it added a step without adding information; the confirmation dialog already
lists every item and its size. Nothing about deletion is persisted.

## ADR-6 — Preferences through the bridge, not `localStorage`
`localStorage` on a `file://` WKWebView is not reliably persistent. Theme and
size threshold go through `prefGet`/`prefSet` into `UserDefaults`, with a
whitelist of keys so the page can't write arbitrary defaults. `localStorage`
is only a first-paint cache for the theme.

## ADR-7 — Universal binary for distribution, native for dev builds
`swift build --arch arm64 --arch x86_64` when `IDENTITY` is set; native
otherwise. Intel Macs stay supported; dev builds stay fast.

## ADR-8 — Test the executable target directly
Rather than splitting a `ReclaimerCore` library, the test target depends on
the executable target and uses `@testable import`. The functions under test
are `internal`; `Bridge` takes an injectable `home` and `Catalog` gains
`load(from:)`. Revisit if the Swift side grows.

## ADR-10 — Per-item delete takes a path, but only as a selector
Granular entries (globs, path lists, `children: true`) let the user delete one
match. The page sends `delete {id, item}` with the item's path. ADR-2 still
holds: the host re-resolves the entry and accepts `item` only if it is in that
fresh set, so the page cannot name anything the catalog doesn't currently
resolve to; the safety gate then runs as for any delete. Entries with a
`deleteCmd` are excluded — a command isn't per-path. Command-listed items
(`itemsCmd` / `deleteItemCmd`, 0.4.0) follow the same rule with a key instead
of a path: the key must come from a fresh listing and is shell-quoted before
substitution, so the page never composes a command.

## ADR-11 — Pipe readers on threads, not GCD
`Shell.run` drains stdout/stderr concurrently. On the global queue those
readers could go unscheduled when several callers were already blocked in
`DispatchGroup.wait` (found by the parallel test run; the app's three scan
workers have the same shape), so the command "hung" until its timeout with
an empty result. Dedicated `Thread`s can't be starved that way.

## ADR-12 — Project folders are configured, with detected defaults
`~/Projects` was hardcoded; on other Macs the six build-output entries
silently measured nothing. Globs now use `$PROJECTS`, expanded to a stored
list that defaults to common folder names that exist. Folders are added
through the system picker so ADR-2 holds (the page never supplies a path
as an instruction), and `~`/`~/Library` are refused so a glob can't reach
app data through this door. Auto-discovering git repositories across the
whole home folder was rejected as slow and surprising.

## ADR-13 — Your-call items go to the Trash, caches don't
Deletes were all `rm -rf`. Real data (the `decide` bucket) now moves to the
Trash so Finder can put it back; the dialog says "Move to Trash" and that
space is freed only once the Trash is emptied. Caches and build output stay
permanent: parked in the Trash they'd reclaim nothing and the disk numbers
would lie. Admin paths and command-driven entries can't be trashed. A
failed trash is an error, not a fallback to `rm`. The trasher is injected so
tests never touch the user's Trash.

## ADR-14 — PolyForm Noncommercial, with the name and icon reserved
Goals: distribute the signed build freely, accept tips only, let anyone read
and rebuild the source, and let nobody sell it. PolyForm Noncommercial 1.0.0
says exactly that in plain language and is written for software (CC licenses
aren't). It permits noncommercial forks, so the LICENSE preamble reserves the
name and icon: a modified build must be renamed, which keeps a tampered
"Reclaimer" from ever looking like the signed one. Not OSI open source — say
"free for noncommercial use", not "open source". Replaces the all-rights-
reserved EULA of 0.1–0.4.

## ADR-15 — Everything the bridge injects
`Bridge` takes its collaborators as init parameters with production
defaults: `home`/`tildeHome` (paths), `defaults` (`UserDefaults`),
`pathPrefix` (fake tools first on PATH), `trasher` (Trash), and `shell`
(`CommandRunner`, default `SystemShell`). Tests pick the seam that fits:
temp directories with the real shell for resolution and deletion, a fake
`xcrun`/`brew` on PATH for the real catalog commands, and `FakeShell` for
failures, timeouts, admin routing and exact command text. No global state,
no test-only build flags.

## ADR-16 — Two shells: plain for measurement, login for tools
Every command went through `zsh -lc`, and the user's profile made each one
cost ~0.8 s regardless of the work — half a minute of a scan was shell
startup. `du`/`find`/`rm` need only system tools, so they now run in
`/bin/sh` with a fixed PATH (5 ms). Catalog commands keep the login shell
because they must find whatever the user's Terminal finds. The mode is an
explicit argument at every call site so a new command can't fall into the
slow path by accident (M3 pins the routing).

## ADR-17 — Two layers against hostile folder names
Every string the page renders can come from the disk: `find` results, a
project-folder path, a `simctl` key. `esc()` escapes `& < > " '` so a name
can't break out of an attribute (R2), and the page's CSP allows only
`script-src 'self'` — no inline script, so even an event-handler attribute
that somehow got in can't run. That required moving the inline scripts to
`boot.js` / `app.js`. Host-injected code (the `--titlebar` user script,
`window.__setTheme`) is exempt from CSP by WebKit's design.

## ADR-18 — Admin work runs in a helper copy of the app
`NSAppleScript` must run on the main thread, so a multi-GB admin `rm -rf`
was a beachball. Alternatives: `osascript` as a subprocess (prompt says
"osascript wants…" — a trust hit for a deletion tool) or authorising
in-process first and running out-of-process (the admin credential is
per-process — `shared: false` in the authorization db — so that prompts
twice). Chosen: re-launch Reclaimer's own signed executable with `--admin
<command>`; that process runs the AppleScript on its main thread and exits
with the status. One prompt, "Allow administrator access for Reclaimer?",
the app stays responsive, no helper tool to install or trust (ADR-4 holds).

## ADR-19 — Swift 6 language mode
`swift-tools-version:6.0` turns on strict concurrency for good. The one
structural consequence: `Bridge` keeps its `WKScriptMessageHandler`
conformance in an extension (that protocol is main-actor, and declaring it
on the class made every method main-actor), and the message body crosses
to the background queue as `Data` rather than a non-Sendable dictionary.
`Diagnostics` is `Sendable` outright (a `Calendar`-based timestamp replaced
the `DateFormatter`). No SwiftLint/SwiftFormat: one maintainer, consistent
style, and a linter would be a dependency for contributors to install; an
`.editorconfig` covers the basics. Revisit when there are regular contributors.
Toolchain floor: Xcode 16.4 (Swift 6.0), enforced by CI. Its compiler does not
infer main-actor isolation for a closure handed to `DispatchQueue.main.sync`,
where Xcode 27's does — isolation is spelled out (`@MainActor` helper +
`MainActor.assumeIsolated`) rather than left to inference.

## ADR-20 — Rename to Backspacer (decided and applied 2026-09-20)
"Reclaimer" is also a paid disk cleaner by MNZN, LLC on the Mac App Store
(since 2024, actively updated, "developer caches" on its feature list). Same
name, same category, same platform: every search lands on theirs, and a
tampered build could pass for either. The rename is a marketing and
trust decision, not a legal one — we are not on the App Store.

Seven rounds of candidates were checked against the Mac and iOS App Stores,
GitHub repository names, Homebrew casks and registry RDAP for `.app`, `.dev`
and `.com`. Rejected: everything on the "reclaim" root (Hyperspace "Reclaim
Disk Space", "Reclaim Space", "Reclaim: Phone Storage Cleaner" share the
shelf); Decruft (decruft.app is a live site); DevClaimer — clean everywhere,
but one spoken syllable from DevCleaner for Xcode, a Mac app in the same
niche with a Homebrew cask, so "get DevClaimer" is heard as DevCleaner;
Reclaimer(y) as a wordplay on the (y/n) prompt — not a rename, the
conflict stays.

Chosen: **Backspacer** — the key that deletes what came before. No product
in the niche shares it; backspacer.app and backspacer.dev were unregistered
on 2026-09-20 (.com is parked). Costs accepted: Pearl Jam's 2009 album owns
web search for the bare word — embraced rather than fought: the tagline is
"I got some if you need it" — a line from the album's "Got Some", read
here as the app offering disk space (the maintainer's own nod; it sits
under the wordmark in the app header, carrying the reclaimable total as an
aside once something is measured, and neither the app nor the site names the band or claims a connection, and the line stays a
seven-word fragment, not a lyric reproduction) — and an iOS
"Backspace - Photo Cleaner" shares the root. The `(y)` device from the terminal-prompt idea was dropped
altogether (2026-09-20, after the site's first draft carried it): the app's
header is plain "Backspacer", and the site matches.

Consequences when applied (one commit, one changelog line, first release
under the new name is 0.8.0): app and bundle name, `CFBundleIdentifier`
`com.antonkulikov.backspacer` (macOS treats it as a new app — Full Disk
Access must be granted again, window frame and preferences start fresh,
`ui.*` defaults are not migrated), log folder `~/Library/Logs/Backspacer/`,
GitHub repository renamed (the old URL redirects), DMG and release titles,
the reserved-name clause in LICENSE, README, About panel, docs and tests.
Applied in full, two steps further than first planned: the notarytool
keychain profile was re-created as `Backspacer` (the maintainer's step), and
the internal names — `Bridge.handlerName`, `window.__backspacerReply`, the
test target, temp-dir prefixes in tests — went too, so `git grep -i
reclaimer` finds only history: this ADR, the changelog, the README's
"formerly" note and the task log. Test K6 keeps it that way. No
`UserDefaults` migration from `com.antonkulikov.reclaimer`: the app is new to
macOS and asks for Full Disk Access and project folders again (README says so).

## ADR-9 — Swift Testing, not XCTest
New target, Xcode 27 toolchain; Swift Testing's parameterised tests suit the
path-list cases in the safety gate. Run with `swift test`.
