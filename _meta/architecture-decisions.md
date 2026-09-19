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

## ADR-9 — Swift Testing, not XCTest
New target, Xcode 27 toolchain; Swift Testing's parameterised tests suit the
path-list cases in the safety gate. Run with `swift test`.
