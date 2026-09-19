import Foundation
import Testing
@testable import Reclaimer

/// Per-item granularity, run against a throwaway directory that stands in for the home folder.
@Suite struct ItemTests {
    let home: URL
    let bridge: Bridge
    let fm = FileManager.default

    static func blob(_ home: URL, _ rel: String, mb: Int) throws {
        let url = home.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: mb * 1024 * 1024).write(to: url)
    }

    init() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("reclaimer-home-\(UUID().uuidString)")
        func blob(_ rel: String, mb: Int) throws { try Self.blob(home, rel, mb: mb) }
        try blob("Projects/a/node_modules/x.bin", mb: 1)
        try blob("Projects/a/node_modules/x/node_modules/deep.bin", mb: 1)   // pruned: inside a match
        try blob("Projects/b/node_modules/y.bin", mb: 2)
        try blob("Library/Developer/Xcode/iOS DeviceSupport/17.0/s.bin", mb: 1)
        try blob("Library/Developer/Xcode/iOS DeviceSupport/18.0/s.bin", mb: 2)
        try blob("Library/Caches/big/b.bin", mb: 3)
        try blob("Library/Caches/small/s.bin", mb: 1)
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "g", "group": "t", "bucket": "regen", "label": "node_modules",
            "glob": { "root": "~/Projects", "name": "node_modules", "maxdepth": 4, "type": "d" } },
          { "id": "c", "group": "t", "bucket": "decide", "label": "DeviceSupport",
            "path": "~/Library/Developer/Xcode/iOS DeviceSupport", "children": true },
          { "id": "p", "group": "t", "bucket": "safe", "label": "Caches", "path": "~/Library/Caches" },
          { "id": "k", "group": "t", "bucket": "safe", "label": "custom", "path": "~/Library/Caches", "deleteCmd": "true" }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
        cat.rawJSON = json
        // Paths in the catalog say "~"; the bridge expands them with the real HOME, so point them at the fixture.
        self.home = home
        self.bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path)
    }

    func cleanup() { try? fm.removeItem(at: home) }
    func items(_ r: Any) -> [[String: Any]] { ((r as? [String: Any])?["items"] as? [[String: Any]]) ?? [] }
    func paths(_ r: Any) -> [String] { items(r).compactMap { $0["path"] as? String }.map { $0.replacingOccurrences(of: home.path + "/", with: "") } }

    @Test("I1 — glob size lists each match with its own bytes, pruned")
    func globItems() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "size", args: ["id": "g"])
        #expect(paths(r).sorted() == ["Projects/a/node_modules", "Projects/b/node_modules"])
        let bytes = items(r).compactMap { $0["bytes"] as? Int64 }
        #expect(bytes.allSatisfy { $0 >= 1_000_000 })
        #expect(((r as? [String: Any])?["bytes"] as? Int64 ?? 0) >= 3_000_000)
    }

    @Test("I2 — children: true lists immediate subfolders")
    func childrenItems() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "size", args: ["id": "c"])
        #expect(paths(r) == ["Library/Developer/Xcode/iOS DeviceSupport/17.0", "Library/Developer/Xcode/iOS DeviceSupport/18.0"])
    }

    @Test("I3 — a plain path entry has no items")
    func plainNoItems() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "size", args: ["id": "p"]) as? [String: Any]
        #expect(r?["items"] == nil)
    }

    @Test("I4 — an item outside the fresh resolve is refused and nothing is removed")
    func refusesForeignItem() throws {
        defer { cleanup() }
        for bad in [home.path + "/Projects/a", home.path + "/Library/Caches", "/tmp", home.path + "/Projects/a/node_modules/x/node_modules"] {
            #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "g", "item": bad]) }
        }
        #expect(fm.fileExists(atPath: home.path + "/Projects/a"))
        #expect(fm.fileExists(atPath: home.path + "/Projects/a/node_modules/x/node_modules"))
        #expect(fm.fileExists(atPath: home.path + "/Library/Caches"))
    }

    @Test("I5 — deleting one match leaves the others")
    func deletesOneItem() throws {
        defer { cleanup() }
        let target = home.path + "/Projects/a/node_modules"
        let r = try bridge.handle(op: "delete", args: ["id": "g", "item": target]) as? [String: Any]
        #expect((r?["freedBytes"] as? Int64 ?? 0) > 0)
        #expect(!fm.fileExists(atPath: target))
        #expect(fm.fileExists(atPath: home.path + "/Projects/b/node_modules"))
        #expect(fm.fileExists(atPath: home.path + "/Projects/a"))
    }

    @Test("I6 — entries with a deleteCmd have no per-item delete")
    func noItemDeleteWithCustomCmd() throws {
        defer { cleanup() }
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "k", "item": home.path + "/Library/Caches"]) }
    }

    @Test("I7 — info on a plain path is a size breakdown, largest first")
    func infoBreakdown() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "info", args: ["id": "p"]) as? [String: Any]
        let lines = (r?["text"] as? String ?? "").split(separator: "\n").map(String.init)
        try #require(lines.count == 2, Comment(rawValue: lines.joined(separator: " | ")))
        #expect(lines[0].hasSuffix("big"))
        #expect(lines[1].hasSuffix("small"))
        #expect(lines[0].contains("MB"))
    }

    @Test("I8 — parseDu")
    func parseDu() {
        let out = "1024\t/a/x\n2048\t/a/y z\n3072\ttotal\n"
        let parsed = Bridge.parseDu(out)
        #expect(parsed.map(\.path) == ["/a/x", "/a/y z"])
        #expect(parsed.map(\.kb) == [1024, 2048])
    }
}
