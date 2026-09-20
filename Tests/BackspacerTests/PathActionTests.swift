import Testing
import Foundation
import AppKit
@testable import Backspacer

// O-tests: the context menu's path actions. The page names a row (entry id) or a Details item
// (its selector); the bridge resolves and validates the path itself and hands a URL to the opener.
@Suite struct PathActionTests {
    final class Recorder: @unchecked Sendable { var opened: [(URL, Bridge.Opener)] = [] }
    let home: URL
    let bridge: Bridge
    let rec = Recorder()
    let fm = FileManager.default

    init() throws {
        home = fm.temporaryDirectory.appendingPathComponent("backspacer-open-\(UUID().uuidString)")
        for d in ["Library/Developer/Xcode/iOS DeviceSupport/17.0", "Library/Developer/Xcode/iOS DeviceSupport/18.0", "Library/Caches/x"] {
            try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "c", "group": "t", "bucket": "decide", "label": "DeviceSupport", "path": "~/Library/Developer/Xcode/iOS DeviceSupport", "children": true },
          { "id": "x", "group": "t", "bucket": "safe", "label": "X cache", "path": "~/Library/Caches/x" }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8)); cat.rawJSON = json
        let r = rec
        bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path, diagnostics: Fixture.quiet, opener: { url, with in r.opened.append((url, with)) })
    }
    func cleanup() { try? fm.removeItem(at: home) }

    @Test("O1 open: an entry opens its first path with the chosen app")
    func openEntry() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "open", args: ["id": "x", "with": "terminal"]) as? [String: Any]
        #expect(r?["path"] as? String == home.path + "/Library/Caches/x")
        #expect(rec.opened.map { $0.0.path } == [home.path + "/Library/Caches/x"])
        #expect(rec.opened.first?.1 == .terminal)
    }

    @Test("O2 open: a Details item must be one of the entry's own items")
    func openItem() throws {
        defer { cleanup() }
        let item = home.path + "/Library/Developer/Xcode/iOS DeviceSupport/18.0"
        let r = try bridge.handle(op: "open", args: ["id": "c", "item": item, "with": "terminal"]) as? [String: Any]
        #expect(r?["path"] as? String == item)
        #expect(throws: (any Error).self) { try bridge.handle(op: "open", args: ["id": "c", "item": home.path + "/Library/Caches/x", "with": "terminal"]) }
        #expect(throws: (any Error).self) { try bridge.handle(op: "open", args: ["id": "c", "item": "/etc", "with": "terminal"]) }
        #expect(rec.opened.count == 1, "a rejected selector opens nothing")
    }

    @Test("O3 open: Terminal is the only app the page may name")
    func openWith() throws {
        defer { cleanup() }
        #expect(throws: (any Error).self) { try bridge.handle(op: "open", args: ["id": "x", "with": "finder"]) }
        #expect(throws: (any Error).self) { try bridge.handle(op: "open", args: ["id": "x"]) }
        #expect(rec.opened.isEmpty)
    }
}
