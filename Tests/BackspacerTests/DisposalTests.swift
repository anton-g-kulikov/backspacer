import Foundation
import Testing
@testable import Backspacer

/// Your-call items go to the Trash; caches are removed for good. A recording trasher stands in
/// for FileManager.trashItem so the user's real Trash is never touched.
@Suite struct DisposalTests {
    final class Recorder: @unchecked Sendable { var trashed: [String] = []; var fail = false }
    let home: URL
    let bridge: Bridge
    let recorder = Recorder()
    let fm = FileManager.default

    init() throws {
        let home = fm.temporaryDirectory.appendingPathComponent("backspacer-trash-\(UUID().uuidString)")
        for d in ["Library/Caches/x", "Library/Developer/Xcode/Archives/2026-01-01", "Library/Developer/Xcode/Archives/2026-02-02", "Library/Android/sdk/ndk", "Library/Application Support/App/data"] {
            try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
            try Data(repeating: 0, count: 1024).write(to: home.appendingPathComponent(d + "/f.bin"))
        }
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "cache", "group": "t", "bucket": "safe",   "label": "cache",    "path": "~/Library/Caches" },
          { "id": "regen", "group": "t", "bucket": "regen",  "label": "regen",    "path": "~/Library/Caches" },
          { "id": "data",  "group": "t", "bucket": "decide", "label": "app data", "path": "~/Library/Application Support/App/data" },
          { "id": "arch",  "group": "t", "bucket": "decide", "label": "archives", "path": "~/Library/Developer/Xcode/Archives", "children": true },
          { "id": "admin", "group": "t", "bucket": "decide", "label": "admin",    "path": "~/Library/Android/sdk/ndk", "sudo": true },
          { "id": "cmd",   "group": "t", "bucket": "decide", "label": "by cmd",   "path": "~/Library/Android/sdk/ndk", "deleteCmd": "true" }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8)); cat.rawJSON = json
        let rec = recorder
        self.home = home
        self.bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path,
                             trasher: { url in
                                 if rec.fail { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "trash refused"]) }
                                 rec.trashed.append(url.path); try FileManager.default.removeItem(at: url)
                             })
    }
    func cleanup() { try? fm.removeItem(at: home) }
    func e(_ id: String) -> Catalog.Entry { bridge.catalogEntry(id)! }

    @Test("D1 — routing by bucket, admin and custom command")
    func routing() {
        defer { cleanup() }
        #expect(bridge.disposal(of: e("data")) == .trash)
        #expect(bridge.disposal(of: e("arch")) == .trash)
        #expect(bridge.disposal(of: e("cache")) == .permanent)
        #expect(bridge.disposal(of: e("regen")) == .permanent)
        #expect(bridge.disposal(of: e("admin")) == .permanent)
        #expect(bridge.disposal(of: e("cmd")) == .permanent)
    }

    @Test("D2 — a Your-call folder is trashed, not rm'd")
    func trashesWholeEntry() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "delete", args: ["id": "data"]) as? [String: Any]
        let p = home.path + "/Library/Application Support/App/data"
        #expect(recorder.trashed == [p])
        #expect(!fm.fileExists(atPath: p))
        #expect(r?["trashed"] as? Bool == true)
    }

    @Test("D3 — per-item delete of a Your-call child is trashed")
    func trashesItem() throws {
        defer { cleanup() }
        let child = home.path + "/Library/Developer/Xcode/Archives/2026-01-01"
        let r = try bridge.handle(op: "delete", args: ["id": "arch", "item": child]) as? [String: Any]
        #expect(recorder.trashed == [child])
        #expect(!fm.fileExists(atPath: child))
        #expect(fm.fileExists(atPath: home.path + "/Library/Developer/Xcode/Archives/2026-02-02"))
        #expect(r?["trashed"] as? Bool == true)
    }

    @Test("D4 — if trashing fails nothing is removed")
    func trashFailure() {
        defer { cleanup() }
        recorder.fail = true
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "data"]) }
        #expect(fm.fileExists(atPath: home.path + "/Library/Application Support/App/data/f.bin"))
    }

    @Test("D5 — caches are removed permanently")
    func permanentCache() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "delete", args: ["id": "cache"]) as? [String: Any]
        #expect(recorder.trashed.isEmpty)
        #expect(!fm.fileExists(atPath: home.path + "/Library/Caches"))
        #expect(r?["trashed"] == nil)
    }
}
