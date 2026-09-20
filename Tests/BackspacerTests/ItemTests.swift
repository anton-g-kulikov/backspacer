import Foundation
import Testing
@testable import Backspacer

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
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("backspacer-home-\(UUID().uuidString)")
        func blob(_ rel: String, mb: Int) throws { try Self.blob(home, rel, mb: mb) }
        try blob("Projects/a/node_modules/x.bin", mb: 1)
        try blob("Projects/a/node_modules/x/node_modules/deep.bin", mb: 1)   // pruned: inside a match
        try blob("Projects/b/node_modules/y.bin", mb: 3)   // a totals 2 MB with its nested folder
        try blob("Library/Developer/Xcode/iOS DeviceSupport/17.0/s.bin", mb: 1)
        try blob("Library/Developer/Xcode/iOS DeviceSupport/18.0/s.bin", mb: 2)
        try blob("Library/Caches/big/b.bin", mb: 3)
        try blob("Library/Caches/small/s.bin", mb: 1)
        try blob("Library/Application Support/MobileSync/Backup/ABCD-1/Manifest.db", mb: 1)
        try blob("Library/Application Support/MobileSync/Backup/EFGH-2/Manifest.db", mb: 1)
        let plist = home.appendingPathComponent("Library/Application Support/MobileSync/Backup/ABCD-1/Info.plist")
        try PropertyListSerialization.data(fromPropertyList: ["Device Name": "Anton's iPhone", "Product Type": "iPhone16,1"], format: .xml, options: 0).write(to: plist)
        try blob("Library/Developer/Xcode/Archives/real/f.bin", mb: 1)
        try blob("Library/Caches/target/keep.bin", mb: 1)
        try fm.createSymbolicLink(atPath: home.path + "/Library/Developer/Xcode/Archives/linked", withDestinationPath: home.path + "/Library/Caches/target")
        try blob("Projects/n/.next/real/f.bin", mb: 1)
        try fm.createSymbolicLink(atPath: home.path + "/Projects/n/.next/cache", withDestinationPath: home.path + "/Library/Caches/target")
        try fm.createSymbolicLink(atPath: home.path + "/Library/Caches/alias", withDestinationPath: home.path + "/Library/Caches/target")
        for d in ["Library/Logs/Backspacer", "Library/Logs/DiagnosticReports", "Library/Logs/Zoom", "Library/Logs/Notion"] { try blob("\(d)/x.log", mb: 1) }
        try blob(".android/avd/Pixel_7.avd/userdata.img", mb: 2)
        try blob(".android/avd/Tablet.avd/userdata.img", mb: 1)
        try "path=\(home.path)/.android/avd/Pixel_7.avd\n".write(to: home.appendingPathComponent(".android/avd/Pixel_7.ini"), atomically: true, encoding: .utf8)
        try "path=\(home.path)/.android/avd/Tablet.avd\n".write(to: home.appendingPathComponent(".android/avd/Tablet.ini"), atomically: true, encoding: .utf8)
        try "orphan".write(to: home.appendingPathComponent(".android/avd/Stray.ini"), atomically: true, encoding: .utf8)
        for d in ["App/Cache", "App/Code Cache", "App/Service Worker/CacheStorage", "App/Other", "App/Cache/inner", "Two/GPUCache"] {
            try blob("Library/Application Support/\(d)/f.bin", mb: 1)
        }
        try blob("Library/Application Support/Code/User/workspaceStorage/aaa1/state.vscdb", mb: 2)
        try blob("Library/Application Support/Code/User/workspaceStorage/bbb2/state.vscdb", mb: 1)
        try blob("Library/Application Support/Code/User/workspaceStorage/ccc3/state.vscdb", mb: 1)
        let ws = home.appendingPathComponent("Library/Application Support/Code/User/workspaceStorage")
        try #"{"folder": "file://\#(home.path)/Projects/my%20app"}"#.write(to: ws.appendingPathComponent("aaa1/workspace.json"), atomically: true, encoding: .utf8)
        try #"{"workspace": "file:///Volumes/Work/team.code-workspace"}"#.write(to: ws.appendingPathComponent("bbb2/workspace.json"), atomically: true, encoding: .utf8)
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "g", "group": "t", "bucket": "regen", "label": "node_modules",
            "glob": { "root": "~/Projects", "name": "node_modules", "maxdepth": 4, "type": "d" } },
          { "id": "c", "group": "t", "bucket": "decide", "label": "DeviceSupport",
            "path": "~/Library/Developer/Xcode/iOS DeviceSupport", "children": true },
          { "id": "p", "group": "t", "bucket": "safe", "label": "Caches", "path": "~/Library/Caches" },
          { "id": "k", "group": "t", "bucket": "safe", "label": "custom", "path": "~/Library/Caches", "deleteCmd": "true" },
          { "id": "bk", "group": "t", "bucket": "decide", "label": "backups", "children": true,
            "path": "~/Library/Application Support/MobileSync/Backup",
            "childLabel": { "file": "Info.plist", "keys": ["Device Name"] } },
          { "id": "el", "group": "t", "bucket": "safe", "label": "electron",
            "glob": { "root": "~/Library/Application Support", "names": ["Cache", "Code Cache", "GPUCache"], "pathPatterns": ["*/Service Worker/CacheStorage"], "maxdepth": 3, "type": "d" } },
          { "id": "arch", "group": "t", "bucket": "safe", "label": "archives", "path": "~/Library/Developer/Xcode/Archives", "children": true },
          { "id": "next", "group": "t", "bucket": "safe", "label": "next", "glob": { "root": "~/Projects", "name": ".next", "maxdepth": 3, "type": "d", "then": "cache" } },
          { "id": "alias", "group": "t", "bucket": "safe", "label": "alias", "path": "~/Library/Caches/alias" },
          { "id": "logs", "group": "t", "bucket": "safe", "label": "logs", "path": "~/Library/Logs", "children": true, "exclude": ["Backspacer", "DiagnosticReports"] },
          { "id": "avd", "group": "t", "bucket": "safe", "label": "avds", "path": "~/.android/avd", "children": true, "companion": ".ini" },
          { "id": "w", "group": "t", "bucket": "safe", "label": "workspaces", "children": true,
            "path": "~/Library/Application Support/Code/User/workspaceStorage",
            "childLabel": { "file": "workspace.json", "keys": ["folder", "workspace"] } }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
        cat.rawJSON = json
        // Paths in the catalog say "~"; the bridge expands them with the real HOME, so point them at the fixture.
        self.home = home
        self.bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path, diagnostics: Fixture.quiet)
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
        #expect(paths(r).sorted() == ["Library/Developer/Xcode/iOS DeviceSupport/17.0", "Library/Developer/Xcode/iOS DeviceSupport/18.0"])
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
        try #require(lines.count >= 2, Comment(rawValue: lines.joined(separator: " | ")))
        #expect(lines[0].hasSuffix("big"))
        #expect(lines.contains { $0.hasSuffix("small") })
        #expect(lines[0].contains("MB"))
    }

    @Test("I9 — display names: relative to the project folder, or the child's name")
    func displayNames() throws {
        defer { cleanup() }
        let g = items(try bridge.handle(op: "size", args: ["id": "g"])).compactMap { $0["display"] as? String }
        #expect(g.sorted() == ["a/node_modules", "b/node_modules"])
        let c = items(try bridge.handle(op: "size", args: ["id": "c"])).compactMap { $0["display"] as? String }
        #expect(c.sorted() == ["17.0", "18.0"])
    }

    @Test("I10 — largest first")
    func sortedBySize() throws {
        defer { cleanup() }
        #expect(paths(try bridge.handle(op: "size", args: ["id": "g"])) == ["Projects/b/node_modules", "Projects/a/node_modules"])
        #expect(paths(try bridge.handle(op: "size", args: ["id": "c"])) == ["Library/Developer/Xcode/iOS DeviceSupport/18.0", "Library/Developer/Xcode/iOS DeviceSupport/17.0"])
    }

    @Test("I11 — childLabel reads the label from a JSON file inside each child")
    func childLabels() throws {
        defer { cleanup() }
        let w = items(try bridge.handle(op: "size", args: ["id": "w"])).compactMap { $0["display"] as? String }
        #expect(w == ["~/Projects/my app", "/Volumes/Work/team.code-workspace", "ccc3"], Comment(rawValue: w.joined(separator: " | ")))
    }

    @Test("I12 — childLabel reads a property list too")
    func plistLabel() throws {
        defer { cleanup() }
        let names = items(try bridge.handle(op: "size", args: ["id": "bk"])).compactMap { $0["display"] as? String }.sorted()
        #expect(names == ["Anton's iPhone", "EFGH-2"], Comment(rawValue: names.joined(separator: " | ")))
    }

    @Test("I13 — names + pathPatterns at depth 3, pruned")
    func electronGlob() throws {
        defer { cleanup() }
        let found = paths(try bridge.handle(op: "size", args: ["id": "el"])).map { $0.replacingOccurrences(of: "Library/Application Support/", with: "") }.sorted()
        #expect(found == ["App/Cache", "App/Code Cache", "App/Service Worker/CacheStorage", "Two/GPUCache"], Comment(rawValue: found.joined(separator: " | ")))
    }

    @Test("I14 — symlinks are never delete targets")
    func symlinkTargets() throws {
        defer { cleanup() }
        let target = home.path + "/Library/Caches/target/keep.bin"
        // a symlinked child
        let link = home.path + "/Library/Developer/Xcode/Archives/linked"
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "arch", "item": link]) }
        #expect(fm.fileExists(atPath: target) && (try? fm.destinationOfSymbolicLink(atPath: link)) != nil)
        // a symlinked glob.then target
        let then = home.path + "/Projects/n/.next/cache"
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "next", "item": then]) }
        #expect(fm.fileExists(atPath: target))
        // a whole entry whose path is a symlink
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "alias"]) }
        #expect(fm.fileExists(atPath: target) && (try? fm.destinationOfSymbolicLink(atPath: home.path + "/Library/Caches/alias")) != nil)
    }

    @Test("I15 — exclude keeps our own log and crash reports out of a logs sweep")
    func excludes() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "size", args: ["id": "logs"]) as? [String: Any]
        let names = ((r?["items"] as? [[String: Any]]) ?? []).compactMap { $0["display"] as? String }.sorted()
        #expect(names == ["Notion", "Zoom"], Comment(rawValue: names.joined(separator: " | ")))
        let expected: Int64 = 2 * 1024 * 1024
        #expect((r?["bytes"] as? NSNumber)?.int64Value == expected, "total counts the listed items only")
        _ = try bridge.handle(op: "delete", args: ["id": "logs"])
        let logs = home.path + "/Library/Logs"
        #expect(fm.fileExists(atPath: logs + "/Backspacer/x.log") && fm.fileExists(atPath: logs + "/DiagnosticReports/x.log"))
        #expect(!fm.fileExists(atPath: logs + "/Zoom") && !fm.fileExists(atPath: logs + "/Notion"))
        #expect(fm.fileExists(atPath: logs), "the parent folder stays")
    }

    @Test("I16 — companion files go with their child (AVDs)")
    func companions() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "size", args: ["id": "avd"]) as? [String: Any]
        let names = ((r?["items"] as? [[String: Any]]) ?? []).compactMap { $0["display"] as? String }
        #expect(names == ["Pixel_7", "Tablet"], Comment(rawValue: names.joined(separator: " | ")))
        let avd = home.path + "/.android/avd"
        _ = try bridge.handle(op: "delete", args: ["id": "avd", "item": avd + "/Pixel_7.avd"])
        #expect(!fm.fileExists(atPath: avd + "/Pixel_7.avd") && !fm.fileExists(atPath: avd + "/Pixel_7.ini"))
        #expect(fm.fileExists(atPath: avd + "/Tablet.avd") && fm.fileExists(atPath: avd + "/Tablet.ini") && fm.fileExists(atPath: avd + "/Stray.ini"))
        // a companion that is a symlink is refused, and then nothing is removed
        try fm.createSymbolicLink(atPath: avd + "/Tablet.ini.bak", withDestinationPath: avd + "/Stray.ini")
        try fm.removeItem(atPath: avd + "/Tablet.ini"); try fm.createSymbolicLink(atPath: avd + "/Tablet.ini", withDestinationPath: avd + "/Stray.ini")
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "avd", "item": avd + "/Tablet.avd"]) }
        #expect(fm.fileExists(atPath: avd + "/Tablet.avd/userdata.img"))
    }

    @Test("I8 — parseDu")
    func parseDu() {
        let out = "1024\t/a/x\n2048\t/a/y z\n3072\ttotal\n"
        let parsed = Bridge.parseDu(out)
        #expect(parsed.map(\.path) == ["/a/x", "/a/y z"])
        #expect(parsed.map(\.kb) == [1024, 2048])
    }
}
