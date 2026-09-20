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
