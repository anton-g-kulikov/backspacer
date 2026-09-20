import Foundation
import Testing
@testable import Backspacer

@Suite struct PrefTests {
    let bridge = try! Fixture.bridge()

    @Test("P1 — known keys are accepted and namespaced", arguments: ["theme", "minSize"])
    func knownKeys(key: String) throws {
        #expect(try bridge.prefKey(["key": key]) == "ui." + key)
    }

    @Test("P2 — unknown keys throw", arguments: ["token", "NSQuitAlwaysKeepsWindows", "", "ui.theme"])
    func unknownKeys(key: String) {
        #expect(throws: (any Error).self) { try bridge.prefKey(["key": key]) }
    }

    @Test("P2b — missing or non-string key throws")
    func badKeyType() {
        #expect(throws: (any Error).self) { try bridge.prefKey([:]) }
        #expect(throws: (any Error).self) { try bridge.prefKey(["key": 42]) }
    }

    @Test("P3 — values must be short strings")
    func values() throws {
        #expect(try bridge.prefValue(["value": "terminal"]) == "terminal")
        #expect(throws: (any Error).self) { try bridge.prefValue(["value": String(repeating: "x", count: 33)]) }
        #expect(throws: (any Error).self) { try bridge.prefValue(["value": 7]) }
        #expect(throws: (any Error).self) { try bridge.prefValue([:]) }
    }
}
