import Foundation
@testable import Backspacer

/// Shared fixtures. Tests run against the real catalog.json so a bad edit fails here.
enum Fixture {
    // Tests/BackspacerTests/Support/Fixture.swift → repo root
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let catalogURL = repoRoot.appendingPathComponent("catalog.json")
    static let home = "/Users/tester"

    /// Every test bridge logs here, never to the user's ~/Library/Logs — a test run must not plant
    /// fake refusals in the file people attach to bug reports (N3 enforces it).
    static let quiet = Diagnostics(file: FileManager.default.temporaryDirectory.appendingPathComponent("backspacer-tests-\(ProcessInfo.processInfo.processIdentifier).log"), maxBytes: 5_000_000)

    static func catalog() throws -> Catalog { try Catalog.load(from: catalogURL) }
    static func bridge() throws -> Bridge { Bridge(catalog: try catalog(), home: home, diagnostics: quiet) }
}
