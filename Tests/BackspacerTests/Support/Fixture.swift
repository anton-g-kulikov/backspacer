import Foundation
@testable import Backspacer

/// Shared fixtures. Tests run against the real catalog.json so a bad edit fails here.
enum Fixture {
    // Tests/BackspacerTests/Support/Fixture.swift → repo root
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let catalogURL = repoRoot.appendingPathComponent("catalog.json")
    static let home = "/Users/tester"

    static func catalog() throws -> Catalog { try Catalog.load(from: catalogURL) }
    static func bridge() throws -> Bridge { Bridge(catalog: try catalog(), home: home) }
}
