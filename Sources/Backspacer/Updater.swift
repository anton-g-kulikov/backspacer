import AppKit
import Sparkle

/// In-app updates (ADR-21), owned by the app delegate. Sparkle does the work — daily check,
/// background download, the "Install and relaunch" prompt, EdDSA + code-signature checks — and
/// this wrapper decides whether to start it, routes the two user controls (About's button and
/// the app menu, the opt-out) to it, and turns "an update was found" into the page's notice.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    /// A build without a feed or a public key (every dev build) has nothing to update from and
    /// nothing to verify against, so the updater is simply not created.
    static func isConfigured(info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty else { return false }
        return true
    }

    /// The About checkbox is stored as `ui.autoUpdateCheck` ("1"/"0"); absent means on.
    static func automaticChecks(pref: String?) -> Bool { pref != "0" }

    private var controller: SPUStandardUpdaterController!
    private let diagnostics: Diagnostics
    /// Set by the app delegate: tells the page a newer version is ready to install.
    var announce: ((_ version: String) -> Void)?

    init(diagnostics: Diagnostics, automaticChecks: Bool) {
        self.diagnostics = diagnostics
        super.init()
        // The controller holds its delegates weakly; this object outlives it (the app delegate owns both).
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.automaticallyChecksForUpdates = automaticChecks
        controller.updater.automaticallyDownloadsUpdates = true   // download in the background; installing still asks
        controller.startUpdater()
        diagnostics.log(.info, "updater: started (automatic checks \(automaticChecks ? "on" : "off"))")
    }

    var version: String { "Sparkle \(Bundle(for: SPUUpdater.self).infoDictionary?["CFBundleShortVersionString"] ?? "?")" }

    func checkForUpdates() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ on: Bool) { controller.updater.automaticallyChecksForUpdates = on }

    // MARK: SPUUpdaterDelegate
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.diagnostics.log(.info, "updater: found \(version)")
            self.announce?(version)
        }
    }
    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in self.diagnostics.log(.info, "updater: up to date") }
    }
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor in self.diagnostics.log(.error, "updater: \(error.localizedDescription)") }
    }
}
