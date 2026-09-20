import Testing
import Foundation
@testable import Backspacer

// PJ-tests: the per-project view's data. The `projects` op lists the project folders under the
// configured roots with a "last touched" date — from git where there is a repository, else from
// the newest source entry — so the page can group build output by project and show staleness.
@Suite struct ProjectsTests {
    let home: URL
    let bridge: Bridge
    let shell = FakeShell()
    let fm = FileManager.default

    init() throws {
        home = fm.temporaryDirectory.appendingPathComponent("backspacer-projects-\(UUID().uuidString)")
        for d in ["Projects/alpha/.git", "Projects/alpha/node_modules", "Projects/beta/src", "Projects/beta/node_modules", "Projects/.hidden", "Work/gamma"] {
            try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try "x".write(to: home.appendingPathComponent("Projects/README.md"), atomically: true, encoding: .utf8)   // a file, not a project
        // beta: the source is old, the build output is fresh — "touched" must follow the source.
        let old = Date(timeIntervalSince1970: 1_700_000_000), fresh = Date()
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: home.appendingPathComponent("Projects/beta/src").path)
        try fm.setAttributes([.modificationDate: fresh], ofItemAtPath: home.appendingPathComponent("Projects/beta/node_modules").path)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: home.appendingPathComponent("Projects/beta").path)
        let suite = "backspacer-projects-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set([home.path + "/Projects", home.path + "/Work"], forKey: "ui.projectRoots")
        shell.on("git -C \(Shell.q(home.path + "/Projects/alpha")) log -1", stdout: "1789000000\n")
        bridge = Bridge(catalog: try Fixture.catalog(), home: home.path, tildeHome: home.path, defaults: defaults, shell: shell, diagnostics: Fixture.quiet)
    }
    func cleanup() { try? fm.removeItem(at: home) }
    func projects() throws -> [[String: Any]] { (try bridge.handle(op: "projects", args: [:]) as? [String: Any])?["projects"] as? [[String: Any]] ?? [] }

    @Test("PJ1 every direct folder of every root is a project; files and hidden folders are not")
    func lists() throws {
        defer { cleanup() }
        let p = try projects()
        #expect(p.map { $0["display"] as? String } == ["~/Projects/alpha", "~/Projects/beta", "~/Work/gamma"])
        #expect(p.map { $0["path"] as? String } == [home.path + "/Projects/alpha", home.path + "/Projects/beta", home.path + "/Work/gamma"])
    }

    @Test("PJ2 a repository's last commit is when it was touched")
    func gitTouched() throws {
        defer { cleanup() }
        let alpha = try #require(try projects().first { ($0["display"] as? String) == "~/Projects/alpha" })
        #expect(alpha["touched"] as? Int == 1_789_000_000)
        #expect(alpha["source"] as? String == "git")
        #expect(shell.modes.allSatisfy { !$0.login }, "plain shell, like measurement")
    }

    @Test("PJ3 without a repository, the newest source entry counts — build output does not")
    func mtimeTouched() throws {
        defer { cleanup() }
        let beta = try #require(try projects().first { ($0["display"] as? String) == "~/Projects/beta" })
        #expect(beta["touched"] as? Int == 1_700_000_000, "node_modules is fresh but is not source")
        #expect(beta["source"] as? String == "mtime")
        #expect(!shell.calls.contains { $0.contains("beta") }, "no git call for a folder without .git")
    }

    @Test("PJ4 no roots, no projects")
    func none() throws {
        defer { cleanup() }
        let d = try #require(UserDefaults(suiteName: "backspacer-projects-none-\(UUID().uuidString)"))
        d.set([String](), forKey: "ui.projectRoots")
        let b = Bridge(catalog: try Fixture.catalog(), home: home.path, tildeHome: home.path, defaults: d, shell: shell, diagnostics: Fixture.quiet)
        let r = try b.handle(op: "projects", args: [:]) as? [String: Any]
        #expect((r?["projects"] as? [[String: Any]])?.isEmpty == true)
    }
}
