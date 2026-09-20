import Testing
import Foundation
@testable import Backspacer

// G-tests: the page can ask the window to follow a drag on its header (WKWebView has no
// drag regions of its own; the bridge calls NSWindow.performDrag with the current event).
@Suite struct WindowDragTests {
    @Test("G1 dragWindow is accepted, quiet, and a no-op without a window")
    func dragWindowOp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backspacer-drag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let diag = Diagnostics(file: dir.appendingPathComponent("Backspacer.log"), maxBytes: 100_000)
        let bridge = Bridge(catalog: try Fixture.catalog(), diagnostics: diag)
        let reply = try bridge.handle(op: "dragWindow", args: [:]) as? [String: Any]
        #expect(reply?["ok"] as? Bool == true)
        let logged = (try? String(contentsOf: diag.file, encoding: .utf8)) ?? ""
        #expect(!logged.contains("dragWindow"), "a drag per mouse-down must not fill the log")
    }
}
