import Testing
import Foundation
@testable import Backspacer

// N-tests: the product name as the binary sees it (ADR-20).
@Suite struct BrandTests {
    @Test("N1 the standard log lives under the product's own folder")
    func logPath() {
        #expect(Diagnostics.standard.file.path.hasSuffix("/Library/Logs/Backspacer/Backspacer.log"))
    }

    @Test("N2 the page ↔ Swift channel is named after the product")
    func handlerName() {
        #expect(Bridge.handlerName == "backspacer")
    }
}

@Suite struct TestHygieneTests {
    @Test("N3 no test builds a Bridge on the user's real diagnostics log")
    func noStandardLogInTests() throws {
        let dir = Fixture.repoRoot.appendingPathComponent("Tests/BackspacerTests")
        let files = try FileManager.default.subpathsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        var offenders: [String] = []
        for f in files {
            let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            // Each `Bridge(` call, up to its balanced close, must name a diagnostics: argument.
            var search = text.startIndex
            while let r = text.range(of: "Bridge(", range: search..<text.endIndex) {
                var depth = 0; var i = r.lowerBound; var call = ""
                while i < text.endIndex {
                    let c = text[i]; call.append(c)
                    if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { break } }
                    i = text.index(after: i)
                }
                if !call.contains("diagnostics:") && !call.contains("Bridge(catalog: Catalog,") { offenders.append("\(f): \(call.prefix(60))") }
                search = i < text.endIndex ? text.index(after: i) : text.endIndex
            }
        }
        #expect(offenders.isEmpty, Comment(rawValue: offenders.joined(separator: "\n")))
    }
}
