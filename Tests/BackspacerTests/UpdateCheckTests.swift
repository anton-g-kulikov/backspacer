import Testing
import Foundation
@testable import Backspacer

// U-tests: About → "Check for updates". Only ever on the user's click; asks GitHub's releases API,
// compares with the running version, and answers with a link — it never downloads or installs.
@Suite struct UpdateCheckTests {
    static let release = """
    { "tag_name": "v0.9.0", "html_url": "https://github.com/anton-g-kulikov/backspacer/releases/tag/v0.9.0",
      "assets": [ { "name": "Backspacer-0.9.0.dmg", "browser_download_url": "https://github.com/anton-g-kulikov/backspacer/releases/download/v0.9.0/Backspacer-0.9.0.dmg" },
                  { "name": "Backspacer-0.9.0.zip", "browser_download_url": "https://example.invalid/zip" } ] }
    """

    @Test("U1 a release parses to version, page and DMG")
    func parse() throws {
        let r = try Updates.parse(Data(Self.release.utf8))
        #expect(r.version == "0.9.0")
        #expect(r.page == "https://github.com/anton-g-kulikov/backspacer/releases/tag/v0.9.0")
        #expect(r.dmg == "https://github.com/anton-g-kulikov/backspacer/releases/download/v0.9.0/Backspacer-0.9.0.dmg")
    }

    @Test("U2 version comparison is numeric per component; dev suffixes are ignored")
    func compare() {
        #expect(Updates.isNewer("0.9.0", than: "0.8.1"))
        #expect(Updates.isNewer("0.10.0", than: "0.9.0"))
        #expect(!Updates.isNewer("0.8.1", than: "0.8.1"))
        #expect(!Updates.isNewer("0.8.0", than: "0.8.1"))
        #expect(Updates.isNewer("1.0", than: "0.99.99"))
        #expect(!Updates.isNewer("0.8.1", than: "0.8.1-3-gabc123"), "a dev build of 0.8.1 is 0.8.1")
        #expect(Updates.isNewer("0.8.2", than: "0.8.1-3-gabc123"))
    }

    final class Recorder: @unchecked Sendable { var urls: [URL] = [] }

    @Test("U3 checkUpdate asks releases/latest and reports newer with the DMG link")
    func op() throws {
        let rec = Recorder()
        let bridge = Bridge(catalog: try Fixture.catalog(), diagnostics: Fixture.quiet, appVersion: "0.8.1",
                            fetch: { url in rec.urls.append(url); return Data(Self.release.utf8) })
        let r = try bridge.handle(op: "checkUpdate", args: [:]) as? [String: Any]
        #expect(rec.urls.map(\.absoluteString) == ["https://api.github.com/repos/anton-g-kulikov/backspacer/releases/latest"])
        #expect(r?["current"] as? String == "0.8.1")
        #expect(r?["latest"] as? String == "0.9.0")
        #expect(r?["newer"] as? Bool == true)
        #expect(r?["url"] as? String == "https://github.com/anton-g-kulikov/backspacer/releases/download/v0.9.0/Backspacer-0.9.0.dmg")
        let same = Bridge(catalog: try Fixture.catalog(), diagnostics: Fixture.quiet, appVersion: "0.9.0", fetch: { _ in Data(Self.release.utf8) })
        let s = try same.handle(op: "checkUpdate", args: [:]) as? [String: Any]
        #expect(s?["newer"] as? Bool == false)
    }

    @Test("U4 offline or odd answers become one plain message")
    func failures() throws {
        struct Offline: Error {}
        let off = Bridge(catalog: try Fixture.catalog(), diagnostics: Fixture.quiet, appVersion: "0.8.1", fetch: { _ in throw Offline() })
        #expect(throws: (any Error).self) { try off.handle(op: "checkUpdate", args: [:]) }
        let odd = Bridge(catalog: try Fixture.catalog(), diagnostics: Fixture.quiet, appVersion: "0.8.1", fetch: { _ in Data("{\"message\":\"rate limited\"}".utf8) })
        #expect(throws: (any Error).self) { try odd.handle(op: "checkUpdate", args: [:]) }
        do { _ = try odd.handle(op: "checkUpdate", args: [:]) } catch {
            #expect(error.localizedDescription.contains("GitHub"), Comment(rawValue: error.localizedDescription))
        }
    }
}
