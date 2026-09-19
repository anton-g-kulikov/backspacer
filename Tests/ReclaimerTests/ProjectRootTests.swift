import Foundation
import Testing
@testable import Reclaimer

@Suite struct ProjectRootTests {
    let home: URL
    let defaults: UserDefaults
    let suite: String
    let bridge: Bridge
    let fm = FileManager.default

    init() throws {
        let home = fm.temporaryDirectory.appendingPathComponent("reclaimer-roots-\(UUID().uuidString)")
        for d in ["Projects/a/node_modules", "Developer/b/node_modules", "Library/Caches/x/node_modules", "Documents/mycode/c"] {
            try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try "x".write(to: home.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let suite = "reclaimer-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "g", "group": "t", "bucket": "regen", "label": "node_modules",
            "glob": { "root": "$PROJECTS", "name": "node_modules", "maxdepth": 4, "type": "d" } }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8)); cat.rawJSON = json
        self.home = home; self.defaults = defaults; self.suite = suite
        self.bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path, defaults: defaults)
    }

    func cleanup() { try? fm.removeItem(at: home); defaults.removePersistentDomain(forName: suite) }
    func rel(_ p: String) -> String { p.replacingOccurrences(of: home.path, with: "~") }

    @Test("R1 — defaults to the common folders that exist")
    func detectsDefaults() {
        defer { cleanup() }
#expect(bridge.projectRoots().map(rel) == ["~/Projects", "~/Developer"])
    }

    @Test("R2 — validation")
    func validation() {
        defer { cleanup() }
        #expect(bridge.isValidProjectRoot(home.path + "/Documents/mycode"))
        for bad in [home.path, home.path + "/Library", home.path + "/Library/Caches", "/tmp", home.path + "/notes.txt", home.path + "/nope"] {
            #expect(!bridge.isValidProjectRoot(bad), Comment(rawValue: bad))
        }
    }

    @Test("R3 — add persists, de-duplicates, rejects invalid")
    func add() throws {
        defer { cleanup() }
        try bridge.addProjectRoot(path: home.path + "/Documents/mycode")
        try bridge.addProjectRoot(path: home.path + "/Documents/mycode/")
        #expect(bridge.projectRoots().map(rel) == ["~/Projects", "~/Developer", "~/Documents/mycode"])
        #expect(throws: (any Error).self) { try bridge.addProjectRoot(path: home.path + "/Library") }
        #expect(bridge.projectRoots().count == 3)
        #expect(defaults.stringArray(forKey: "ui.projectRoots")?.count == 3)   // persisted
    }

    @Test("R4 — remove only what is listed")
    func remove() throws {
        defer { cleanup() }
        try bridge.removeProjectRoot(path: home.path + "/Developer")
        #expect(bridge.projectRoots().map(rel) == ["~/Projects"])
        #expect(throws: (any Error).self) { try bridge.removeProjectRoot(path: home.path + "/Library") }
    }

    @Test("R5 — $PROJECTS globs search every root and nothing else")
    func globAcrossRoots() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "size", args: ["id": "g"]) as? [String: Any]
        let paths = (r?["paths"] as? [String] ?? []).map(rel).sorted()
        #expect(paths == ["~/Developer/b/node_modules", "~/Projects/a/node_modules"])
    }

    @Test("R6 — projectRoots op reply carries display names")
    func opReply() throws {
        defer { cleanup() }
        let r = try bridge.handle(op: "projectRoots", args: [:]) as? [String: Any]
        let roots = r?["roots"] as? [[String: String]] ?? []
        #expect(roots.map { $0["display"] } == ["~/Projects", "~/Developer"])
        #expect(roots.first?["path"] == home.path + "/Projects")
    }
}
