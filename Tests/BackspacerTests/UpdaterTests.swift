import Testing
import Foundation
@testable import Backspacer

// W-tests (updater): Sparkle owns updates (ADR-21). The app only decides whether to start it,
// routes the user's two controls to it, and turns its events into the footer notice.
@Suite @MainActor struct UpdaterTests {
    @Test("W1 the updater starts only when the build carries a feed and a public key")
    func startsWithFeedOnly() {
        #expect(Updater.isConfigured(info: ["SUFeedURL": "https://backspacer.dev/appcast.xml", "SUPublicEDKey": "abc="]))
        #expect(!Updater.isConfigured(info: ["SUPublicEDKey": "abc="]), "no feed: a dev build")
        #expect(!Updater.isConfigured(info: ["SUFeedURL": "https://backspacer.dev/appcast.xml"]), "no key: nothing to verify against")
        #expect(!Updater.isConfigured(info: [:]))
    }

    @Test("W2 the opt-out preference maps onto Sparkle's automatic checks, default on")
    func optOut() {
        #expect(Updater.automaticChecks(pref: nil) == true)
        #expect(Updater.automaticChecks(pref: "1") == true)
        #expect(Updater.automaticChecks(pref: "0") == false)
    }

    @Test("W3 the page's update ops no longer poll GitHub: they report the updater's state")
    func opsRouteToUpdater() throws {
        let bridge = Bridge(catalog: try Fixture.catalog(), diagnostics: Fixture.quiet)
        // No updater attached (a dev build): the manual check says so instead of asking GitHub.
        let r = try bridge.handle(op: "checkUpdate", args: [:]) as? [String: Any]
        #expect(r?["skipped"] as? String == "unconfigured")
        #expect(throws: (any Error).self) { try bridge.handle(op: "autoCheckUpdate", args: [:]) }   // gone with the poll
    }
}
