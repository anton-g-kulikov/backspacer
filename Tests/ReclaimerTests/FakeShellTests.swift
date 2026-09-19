import Foundation
import Testing
@testable import Reclaimer

@Suite struct FakeShellTests {
    let home: URL
    let shell = FakeShell()
    let bridge: Bridge
    let fm = FileManager.default

    init() throws {
        let home = fm.temporaryDirectory.appendingPathComponent("reclaimer-fake-\(UUID().uuidString)")
        // resolvePaths filters non-admin paths by existence, so the folders must exist; nothing inside is read.
        for d in ["Library/Caches", "Projects/my app/node_modules", "Projects/b/node_modules", "Library/Logs"] { try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true) }
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "p",   "group": "t", "bucket": "safe",   "label": "caches", "path": "~/Library/Caches" },
          { "id": "g",   "group": "t", "bucket": "regen",  "label": "nm",     "glob": { "root": "~/Projects", "name": "node_modules", "maxdepth": 3, "type": "d" } },
          { "id": "adm", "group": "t", "bucket": "safe",   "label": "admin",  "path": "/Library/Developer/CoreSimulator/Caches", "sudo": true },
          { "id": "cmd", "group": "t", "bucket": "safe",   "label": "custom", "path": "~/Library/Logs", "deleteCmd": "brew cleanup -s" },
          { "id": "sz",  "group": "t", "bucket": "decide", "label": "sized",  "sizeCmd": "some-tool --kb", "manual": true },
          { "id": "multi", "group": "t", "bucket": "safe", "label": "two", "paths": ["~/Library/Caches", "~/Library/Logs"] },
          { "id": "it",  "group": "t", "bucket": "decide", "label": "items",  "itemsCmd": "list-things", "deleteItemCmd": "rm-thing {key}" }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8)); cat.rawJSON = json
        self.home = home
        self.bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path, shell: shell)
    }
    func cleanup() { try? fm.removeItem(at: home) }
    func n(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }

    @Test("F1 — size runs a quoted du and reads the total line")
    func sizeCommand() throws {
        defer { cleanup() }
        let p = home.path + "/Library/Caches"
        shell.on("du -skxc", stdout: "2048\t\(p)\n2048\ttotal\n")
        let r = try bridge.handle(op: "size", args: ["id": "p"]) as? [String: Any]
        #expect(shell.calls == ["du -skxc '\(p)' 2>/dev/null"])
        let expected: Int64 = 2048 * 1024
        #expect(n(r?["bytes"]) == expected)
    }

    @Test("F2 — a failing du yields 0, not an error")
    func duFails() throws {
        defer { cleanup() }
        shell.on("du -skxc", stdout: "", stderr: "du: boom", status: 1)
        let r = try bridge.handle(op: "size", args: ["id": "p"]) as? [String: Any]
        #expect(n(r?["bytes"]) == 0)
    }

    @Test("F3 — a failing rm surfaces its stderr")
    func rmFails() {
        defer { cleanup() }
        shell.on("rm -rf", stderr: "rm: Permission denied", status: 1)
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "p"]) }
        #expect(shell.calls.contains { $0.hasPrefix("rm -rf '") })
        #expect(shell.adminCalls.isEmpty)
    }

    @Test("F4 — sudo entries go through the admin dialog; cancel is an error")
    func adminRouting() {
        defer { cleanup() }
        shell.on("rm -rf", stderr: "cancelled", status: -128)
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "adm"]) }
        #expect(shell.adminCalls == ["rm -rf '/Library/Developer/CoreSimulator/Caches'"])
        #expect(!shell.calls.contains { $0.hasPrefix("rm") })
    }

    @Test("F5 — glob builds a pruned find and parses NUL-separated output")
    func globCommand() throws {
        defer { cleanup() }
        let root = home.path + "/Projects"
        shell.on("find ", stdout: "\(root)/my app/node_modules\u{0}\(root)/b/node_modules\u{0}")
        shell.on("xargs", stdout: "10\t\(root)/my app/node_modules\n20\t\(root)/b/node_modules\n")
        let r = try bridge.handle(op: "size", args: ["id": "g"]) as? [String: Any]
        #expect(shell.calls.first == "find '\(root)' -maxdepth 3 -type d \\( -name 'node_modules' \\) -prune -print0 2>/dev/null")
        #expect((r?["paths"] as? [String] ?? []).sorted() == ["\(root)/b/node_modules", "\(root)/my app/node_modules"])
        let expected: Int64 = 30 * 1024
        #expect(n(r?["bytes"]) == expected)
    }

    @Test("F6 — garbage from itemsCmd means no items, not an error")
    func garbageItems() throws {
        defer { cleanup() }
        shell.on("list-things", stdout: "not\ttab-separated\nnope\n")
        let r = try bridge.handle(op: "size", args: ["id": "it"]) as? [String: Any]
        #expect((r?["items"] as? [Any])?.isEmpty == true)
        #expect(n(r?["bytes"]) == 0)
    }

    @Test("F7 — non-numeric sizeCmd output is reported as unknown")
    func badSizeCmd() throws {
        defer { cleanup() }
        shell.on("some-tool", stdout: "error: not installed\n")
        let r = try bridge.handle(op: "size", args: ["id": "sz"]) as? [String: Any]
        #expect(r?["bytes"] is NSNull)
    }

    @Test("F9 — several paths are measured in parallel with xargs")
    func parallelDu() throws {
        defer { cleanup() }
        let a = home.path + "/Library/Caches", b = home.path + "/Library/Logs"
        shell.on("xargs", stdout: "10\t\(b)\n30\t\(a)\n")
        let r = try bridge.handle(op: "size", args: ["id": "multi"]) as? [String: Any]
        let cmd = try #require(shell.calls.first { $0.contains("xargs") })
        #expect(cmd == "printf '%s\\0' '\(a)' '\(b)' | xargs -0 -P 2 -n 1 du -skx 2>/dev/null", Comment(rawValue: cmd))
        let expected: Int64 = 40 * 1024
        #expect(n(r?["bytes"]) == expected)
        let items = r?["items"] as? [[String: Any]] ?? []
        #expect(items.map { $0["path"] as? String } == [a, b], "largest first")
        #expect(!shell.calls.contains { $0.hasPrefix("du -skxc") })
    }

    @Test("F10 — a single path still uses plain du")
    func singleDu() throws {
        defer { cleanup() }
        shell.on("du -skxc", stdout: "5\t\(home.path)/Library/Caches\n5\ttotal\n")
        _ = try bridge.handle(op: "size", args: ["id": "p"])
        #expect(!shell.calls.contains { $0.contains("xargs") })
    }

    @Test("F8 — deleteCmd runs verbatim instead of rm")
    func customDelete() throws {
        defer { cleanup() }
        _ = try bridge.handle(op: "delete", args: ["id": "cmd"])
        #expect(shell.calls.contains("brew cleanup -s"))
        #expect(!shell.calls.contains { $0.hasPrefix("rm") })
    }
}
