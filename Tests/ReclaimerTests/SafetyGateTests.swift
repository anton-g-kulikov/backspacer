import Foundation
import Testing
@testable import Reclaimer

@Suite struct SafetyGateTests {
    let bridge = try! Fixture.bridge()
    let home = Fixture.home

    @Test("S1 — roots and user data folders are refused",
          arguments: ["/", "/Users/tester", "/Users/tester/Library", "/Users/tester/Documents",
                      "/Users/tester/Projects", "/Users", "/System", "/Applications"])
    func refusesProtectedRoots(path: String) {
        #expect(!bridge.isSafeToDelete(path))
    }

    @Test("S2 — cache and build folders are allowed",
          arguments: ["/Users/tester/Library/Caches", "/Users/tester/.cache",
                      "/Users/tester/Library/Developer/Xcode/DerivedData",
                      "/Library/Developer/CoreSimulator/Caches"])
    func allowsCaches(path: String) {
        #expect(bridge.isSafeToDelete(path))
    }

    @Test("S3 — anything outside the allowed roots is refused",
          arguments: ["/opt/homebrew", "/private/var/vm", "/Volumes/Other/stuff", "/Users/someone-else/Library/Caches"])
    func refusesOutsideRoots(path: String) {
        #expect(!bridge.isSafeToDelete(path))
    }

    @Test("S4 — top-level visible home folders are refused, dot-folders allowed")
    func topLevelHome() {
        #expect(!bridge.isSafeToDelete(home + "/Anything"))
        #expect(bridge.isSafeToDelete(home + "/.gradle"))
    }

    @Test("S5 — traversal is normalised before the check")
    func traversal() {
        #expect(!bridge.isSafeToDelete(home + "/Library/Caches/../../Documents"))
        #expect(!bridge.isSafeToDelete(home + "/Library/Caches/.."))
    }

    @Test("S6 — relative paths are refused")
    func relative() {
        #expect(!bridge.isSafeToDelete("Library/Caches"))
        #expect(!bridge.isSafeToDelete("~/Library/Caches"))
    }

    @Test("S8 — user data is refused even below depth 2",
          arguments: ["/Users/tester/Documents/Thesis", "/Users/tester/Desktop/notes", "/Users/tester/Pictures/Photos Library.photoslibrary",
                      "/Users/tester/Movies/x", "/Users/tester/Music/x", "/Users/tester/Public/x",
                      "/Users/tester/Library/Mail", "/Users/tester/Library/Mail/V10", "/Users/tester/Library/Messages/x",
                      "/Users/tester/Library/Keychains", "/Users/tester/Library/Mobile Documents/x", "/Users/tester/Library/CloudStorage/Dropbox",
                      "/Users/tester/Library/Group Containers/x", "/Users/tester/Library/Accounts", "/Users/tester/Library/Cookies", "/Users/tester/Library/Safari/x",
                      "/Users/tester/.ssh", "/Users/tester/.ssh/id_ed25519", "/Users/tester/.gnupg/x",
                      "/Users/tester/Library/Caches/Photos Library.photoslibrary", "/Users/tester/.cache/Old.photoslibrary/data"])
    func refusesUserData(path: String) {
        #expect(!bridge.isSafeToDelete(path), Comment(rawValue: path))
    }

    @Test("S8b — inside a configured project folder is exempt")
    func projectFolderExempt() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("reclaimer-gate-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        try fm.createDirectory(at: home.appendingPathComponent("Documents/mycode/app/node_modules"), withIntermediateDirectories: true)
        let suite = "reclaimer-gate-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let b = Bridge(catalog: try Fixture.catalog(), home: home.path, tildeHome: home.path, defaults: defaults)
        #expect(!b.isSafeToDelete(home.path + "/Documents/mycode/app/node_modules"), "not a root yet")
        try b.addProjectRoot(path: home.path + "/Documents/mycode")
        #expect(b.isSafeToDelete(home.path + "/Documents/mycode/app/node_modules"))
        #expect(!b.isSafeToDelete(home.path + "/Documents/Thesis"), "siblings outside the root stay refused")
        #expect(!b.isSafeToDelete(home.path + "/Documents/mycode"), "the root itself is not deletable")
    }

    @Test("S9 — comparisons fold case")
    func caseFolding() {
        #expect(!bridge.isSafeToDelete("/Users/tester/library/MAIL/x"))
        #expect(!bridge.isSafeToDelete("/users/TESTER/Documents/x"))
        #expect(bridge.isSafeToDelete("/Users/tester/LIBRARY/caches"))
    }

    @Test("S10 — allowed roots need a path separator")
    func rootSeparator() {
        #expect(!bridge.isSafeToDelete("/System/Volumes/Data/macOS Install Data-2"))
        #expect(bridge.isSafeToDelete("/System/Volumes/Data/macOS Install Data/x"))
        #expect(bridge.isSafeToDelete("/System/Volumes/Data/macOS Install Data"), "the staged update folder itself is the target")
        #expect(!bridge.isSafeToDelete("/Library/DeveloperX/y"))
    }

    @Test("S11 — symlinks are resolved before the check")
    func symlinks() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("reclaimer-link-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        try fm.createDirectory(at: home.appendingPathComponent("Documents/Thesis"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: home.path + "/Library/Caches/evil", withDestinationPath: home.path + "/Documents")
        let b = Bridge(catalog: try Fixture.catalog(), home: home.path, tildeHome: home.path)
        #expect(!b.isSafeToDelete(home.path + "/Library/Caches/evil"))
        #expect(!b.isSafeToDelete(home.path + "/Library/Caches/evil/Thesis"))
        #expect(b.isSafeToDelete(home.path + "/Library/Caches"))
    }

    @Test("S7 — every static path of a deletable catalog entry passes the gate")
    func catalogPathsPassGate() throws {
        let catalog = try Fixture.catalog()
        for e in catalog.entries where e.isDeletable && e.deleteCmd == nil {
            let paths = (e.path.map { [$0] } ?? []) + (e.paths ?? [])
            for p in paths {
                let resolved = p.hasPrefix("~") ? home + p.dropFirst() : p
                #expect(bridge.isSafeToDelete(resolved), Comment(rawValue: "\(e.id): \(p)"))
            }
        }
    }
}
