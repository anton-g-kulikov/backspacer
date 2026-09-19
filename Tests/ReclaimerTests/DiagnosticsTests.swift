import Foundation
import Testing
@testable import Reclaimer

@Suite struct DiagnosticsTests {
    let dir: URL
    let diag: Diagnostics
    let fm = FileManager.default

    init() {
        dir = fm.temporaryDirectory.appendingPathComponent("reclaimer-diag-\(UUID().uuidString)")
        diag = Diagnostics(file: dir.appendingPathComponent("Logs/Reclaimer.log"), maxBytes: 2_000)
    }
    func cleanup() { try? fm.removeItem(at: dir) }
    func text() -> String { (try? String(contentsOf: diag.file, encoding: .utf8)) ?? "" }

    @Test("L1 — appends timestamped lines, creating the file")
    func appends() {
        defer { cleanup() }
        diag.log(.info, "hello")
        diag.log(.error, "bad thing")
        let lines = text().split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[info\] hello$"#, options: .regularExpression) != nil, Comment(rawValue: String(lines[0])))
        #expect(lines[1].hasSuffix("[error] bad thing"))
    }

    @Test("L2 — rotates once past the size limit")
    func rotates() {
        defer { cleanup() }
        for i in 0..<60 { diag.log(.info, "line \(i) " + String(repeating: "x", count: 40)) }
        let previous = diag.file.deletingPathExtension().appendingPathExtension("previous.log")
        #expect(fm.fileExists(atPath: previous.path))
        let size = (try? fm.attributesOfItem(atPath: diag.file.path)[.size] as? Int) ?? 0
        #expect(size < 2_000)
        #expect(text().contains("line 59"))
    }

    @Test("L3 — one line per message")
    func oneLine() {
        defer { cleanup() }
        diag.log(.info, "first\nsecond\r\nthird")
        #expect(text().split(separator: "\n").count == 1)
        #expect(text().contains("first⏎second⏎third"))
    }

    @Test("L4 — bridge ops are logged, chatter is not")
    func bridgeOps() throws {
        defer { cleanup() }
        let bridge = Bridge(catalog: try Fixture.catalog(), diagnostics: diag)
        _ = try? bridge.handle(op: "catalog", args: [:])
        _ = try? bridge.handle(op: "prefGet", args: ["key": "theme"])
        _ = try? bridge.handle(op: "size", args: ["id": "no-such-entry"])
        _ = try? bridge.handle(op: "info", args: ["id": "cache-brew-orphans"])
        let t = text()
        #expect(!t.contains("] catalog"))
        #expect(!t.contains("] prefGet"))
        #expect(t.contains("[error] size no-such-entry: Unknown catalog entry: no-such-entry"), Comment(rawValue: t))
        #expect(t.range(of: #"\[info\] info cache-brew-orphans ok \(\d+ ms\)"#, options: .regularExpression) != nil, Comment(rawValue: t))
    }

    @Test("L5 — the page's log op")
    func pageLog() throws {
        defer { cleanup() }
        let bridge = Bridge(catalog: try Fixture.catalog(), diagnostics: diag)
        _ = try bridge.handle(op: "log", args: ["level": "error", "message": "TypeError: x is undefined"])
        _ = try bridge.handle(op: "log", args: ["level": "weird", "message": "scan complete"])
        let t = text()
        #expect(t.contains("[error] page: TypeError: x is undefined"))
        #expect(t.contains("[info] page: scan complete"))
    }

    @Test("L7 — scan hints remember each entry's last duration")
    func scanHints() throws {
        defer { cleanup() }
        let suite = "reclaimer-hints-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let shell = FakeShell()
        let bridge = Bridge(catalog: try Fixture.catalog(), defaults: defaults, shell: shell, diagnostics: diag)
        _ = try bridge.handle(op: "size", args: ["id": "cache-brew-orphans"])   // no source: measured instantly
        _ = try bridge.handle(op: "info", args: ["id": "cache-brew-orphans"])   // not a size op: no hint
        let hints = (try bridge.handle(op: "scanHints", args: [:]) as? [String: Any])?["durations"] as? [String: Int] ?? [:]
        #expect(hints["cache-brew-orphans"] != nil)
        #expect(hints.count == 1)
        #expect(defaults.dictionary(forKey: "scan.durations")?["cache-brew-orphans"] != nil)
    }

    @Test("L6 — revealLog replies with the path")
    func reveal() throws {
        defer { cleanup() }
        let bridge = Bridge(catalog: try Fixture.catalog(), diagnostics: diag)
        let r = try bridge.handle(op: "logPath", args: [:]) as? [String: Any]
        #expect(r?["path"] as? String == diag.file.path)
    }
}
