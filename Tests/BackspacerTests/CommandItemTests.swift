import Foundation
import Testing
@testable import Backspacer

/// Command-listed items, run through the real catalog commands against a fake `xcrun`.
@Suite struct CommandItemTests {
    let dir: URL
    let logFile: URL
    let bridge: Bridge
    let fm = FileManager.default

    static let devicesJSON = """
    {"devices": {
      "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
        {"udid": "AAAA-1", "name": "iPhone 17 Pro", "isAvailable": true, "state": "Shutdown", "dataPathSize": 3970445312},
        {"udid": "BBBB-2", "name": "iPad Air 11-inch (M4)", "isAvailable": true, "state": "Shutdown", "dataPathSize": 2026864640}],
      "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
        {"udid": "CCCC-3", "name": "Old phone", "isAvailable": false, "state": "Shutdown", "dataPathSize": 5}]
    }}
    """
    static let runtimesJSON = """
    {"6FBA-RT": {"runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "build": "23F77", "sizeBytes": 8494282293, "deletable": true},
     "0000-RT": {"runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-0", "version": "18.0", "build": "22A3351", "sizeBytes": 7000000000, "deletable": false}}
    """

    init() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("backspacer-xcrun-\(UUID().uuidString)")
        let bin = dir.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        logFile = dir.appendingPathComponent("calls.log")
        try Self.devicesJSON.write(to: dir.appendingPathComponent("devices.json"), atomically: true, encoding: .utf8)
        try Self.runtimesJSON.write(to: dir.appendingPathComponent("runtimes.json"), atomically: true, encoding: .utf8)
        let script = """
        #!/bin/sh
        case "$*" in
          "simctl list devices -j") cat \(Shell.q(dir.appendingPathComponent("devices.json").path)) ;;
          "simctl runtime list -j") cat \(Shell.q(dir.appendingPathComponent("runtimes.json").path)) ;;
          *) echo "$*" >> \(Shell.q(logFile.path)) ;;
        esac
        """
        let xcrun = bin.appendingPathComponent("xcrun")
        try script.write(to: xcrun, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcrun.path)
        bridge = Bridge(catalog: try Fixture.catalog(), pathPrefix: bin.path)
    }

    func cleanup() { try? fm.removeItem(at: dir) }
    func n(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }
    func calls() -> [String] { ((try? String(contentsOf: logFile, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
    func items(_ id: String) throws -> [[String: Any]] {
        let r = try bridge.handle(op: "size", args: ["id": id]) as? [String: Any]
        return r?["items"] as? [[String: Any]] ?? []
    }

    @Test("T1 — devices: one item per available simulator")
    func devices() throws {
        defer { cleanup() }
        let it = try items("xcode-simdevices")
        #expect(it.map { $0["key"] as? String } == ["AAAA-1", "BBBB-2"])
        #expect(it.map { $0["label"] as? String } == ["iPhone 17 Pro · iOS 26.5", "iPad Air 11-inch (M4) · iOS 26.5"])
        let expected: Int64 = 3_970_445_312   // dataPathSize, whole KB
        #expect(n(it.first?["bytes"]) == expected)
    }

    @Test("T2 — runtimes: deletable ones only, total is their sum")
    func runtimes() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "size", args: ["id": "xcode-runtimes"]) as? [String: Any]
        let it = r?["items"] as? [[String: Any]] ?? []
        #expect(it.map { $0["key"] as? String } == ["6FBA-RT"])
        #expect(it.first?["label"] as? String == "iOS 26.5 (23F77)")
        let expected: Int64 = 8_494_282_293 / 1024 * 1024
        #expect(n(r?["bytes"]) == expected)
    }

    @Test("T3 — an unknown key is refused and nothing runs")
    func unknownKey() throws {
        defer { cleanup() }
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "xcode-simdevices", "item": "CCCC-3"]) }
        #expect(throws: (any Error).self) { try bridge.handle(op: "delete", args: ["id": "xcode-simdevices", "item": "AAAA-1; rm -rf /"]) }
        #expect(calls().isEmpty)
    }

    @Test("T4 — erasing one device runs simctl erase with that UDID")
    func eraseDevice() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "delete", args: ["id": "xcode-simdevices", "item": "BBBB-2"]) as? [String: Any]
        #expect(calls().contains("simctl erase BBBB-2"), Comment(rawValue: calls().joined(separator: " | ")))
        let expected: Int64 = 2_026_864_640
        #expect(n(r?["freedBytes"]) == expected)
    }

    @Test("T5 — deleting one runtime runs simctl runtime delete")
    func deleteRuntime() throws {
        defer { cleanup() }
        _ = try bridge.handle(op: "delete", args: ["id": "xcode-runtimes", "item": "6FBA-RT"])
        #expect(calls() == ["simctl runtime delete 6FBA-RT"], Comment(rawValue: calls().joined(separator: " | ")))
    }

    @Test("T8 — ollama list parses into items")
    func ollama() throws {
        defer { cleanup() }
        let ollama = dir.appendingPathComponent("bin/ollama")
        try "#!/bin/sh\nprintf 'NAME               ID              SIZE      MODIFIED\\nllama3.1:8b        46e0c10c039e    4.9 GB    3 weeks ago\\nnomic-embed-text   0a109f422b47    274 MB    5 days ago\\n'\n".write(to: ollama, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ollama.path)
        let it = try items("ollama-models")
        #expect(it.map { $0["key"] as? String } == ["llama3.1:8b", "nomic-embed-text"])
        let kb1: Int64 = Int64(4.9 * 1048576), kb2: Int64 = 274 * 1024
        #expect(n(it[0]["bytes"]) == kb1 * 1024, Comment(rawValue: "\(String(describing: it[0]["bytes"]))"))
        #expect(n(it[1]["bytes"]) == kb2 * 1024)
    }

    @Test("T6 — parseItems")
    func parse() {
        let p = Bridge.parseItems("k1\tLabel one\t10\nbad line\nk2\tLabel two\t20\n\n")
        #expect(p.map(\.key) == ["k1", "k2"])
        #expect(p.map(\.label) == ["Label one", "Label two"])
        #expect(p.map(\.kb) == [10, 20])
    }

    @Test("T7 — itemsCmd and deleteItemCmd come in pairs")
    func pairs() throws {
        let cat = try Fixture.catalog()
        let withItems = cat.entries.filter { $0.itemsCmd != nil || $0.deleteItemCmd != nil }
        #expect(withItems.count >= 2)
        for e in withItems {
            #expect(e.itemsCmd != nil && e.deleteItemCmd?.contains("{key}") == true, Comment(rawValue: e.id))
        }
    }
}
