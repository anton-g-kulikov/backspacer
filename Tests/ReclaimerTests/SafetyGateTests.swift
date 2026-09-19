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
