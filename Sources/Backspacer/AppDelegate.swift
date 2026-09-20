import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var bridge: Bridge!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        Diagnostics.standard.log(.info, "launch: Backspacer \(info["CFBundleShortVersionString"] ?? "dev") (\(info["CFBundleVersion"] ?? "local")), macOS \(os), \(Self.arch)")
        buildMenu()
        #if DEBUG
        // Unbundled runs (Xcode ⌘R, swift run) have no Info.plist, so the Dock shows a generic icon.
        if Bundle.main.infoDictionary?["CFBundleIconFile"] == nil,
           let icon = Resources.url("assets/AppIcon.icns").flatMap({ NSImage(contentsOf: $0) }) {
            NSApp.applicationIconImage = icon
        }
        #endif

        let catalog: Catalog
        do { catalog = try Catalog.load() } catch {
            fatal("Couldn't load catalog.json from the app bundle.\n\(error)")
            return
        }
        bridge = Bridge(catalog: catalog)

        let config = WKWebViewConfiguration()
        config.userContentController.add(bridge, name: Bridge.handlerName)
        let titlebar = Self.titlebarHeight
        config.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.style.setProperty('--titlebar', '\(titlebar)px')",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .windowBackgroundColor
        // Right-click → Inspect Element: on for debug builds, or `defaults write com.antonkulikov.backspacer
        // WebInspector -bool YES` for a release build when a user is helping debug the page (R20).
        #if DEBUG
        let inspectable = true
        #else
        let inspectable = UserDefaults.standard.bool(forKey: "WebInspector")
        #endif
        if #available(macOS 13.3, *) { webView.isInspectable = inspectable }
        bridge.webView = webView
        webView.navigationDelegate = self

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Backspacer"
        window.tabbingMode = .disallowed   // keeps AppKit from adding "Show Tab Bar" to the View menu
        // Traffic lights inside the page: the web view runs under a transparent title bar, and the
        // page keeps its header below it via the --titlebar CSS variable (set before first paint).
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: 760, height: 520)
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("BackspacerMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Load the bundled UI. `allowingReadAccessTo` scopes file:// access to Resources/.
        guard let res = Resources.root else { fatal("No Resources directory in bundle."); return }
        let index = res.appendingPathComponent("web/index.html")
        webView.loadFileURL(index, allowingReadAccessTo: res)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { Diagnostics.standard.log(.info, "quit") }

    private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// WebKit's content process died (memory pressure, a WebKit bug). The window stays; the page
    /// would otherwise be blank. Log it and reload so the user sees the list again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Diagnostics.standard.log(.error, "web content process terminated — reloading the page")
        webView.reload()
    }

    /// Height of a standard titled window's title bar, measured rather than assumed.
    private static var titlebarHeight: CGFloat {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let content = NSWindow.contentRect(forFrameRect: frame, styleMask: [.titled, .fullSizeContentView])
        let inset = NSWindow.contentRect(forFrameRect: frame, styleMask: [.titled])
        return content.height - inset.height
    }

    private func fatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Backspacer can't start"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }

    @objc private func openRepo(_ sender: Any?) { NSWorkspace.shared.open(URL(string: "https://github.com/anton-g-kulikov/backspacer")!) }
    @objc private func openIssues(_ sender: Any?) { NSWorkspace.shared.open(URL(string: "https://github.com/anton-g-kulikov/backspacer/issues/new/choose")!) }
    @objc private func revealLog(_ sender: Any?) { NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.standard.file]) }

    /// View ▸ Glass / Terminal. The page stores the choice through the bridge (UserDefaults "ui.theme").
    @objc private func setTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        webView.evaluateJavaScript("window.__setTheme(\(id.debugDescription))", completionHandler: nil)
    }

    /// Only the bundled page loads inside the window; mailto:/https: links (About panel) go to the system.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, !url.isFileURL {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = UserDefaults.standard.string(forKey: "ui.theme") ?? "glass"
        menu.items.forEach { $0.state = ($0.representedObject as? String) == current ? .on : .off }
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Backspacer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Backspacer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Backspacer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        // Only what the page can actually do: there are no editable fields, so no Undo/Cut/Paste.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.delegate = self   // menuNeedsUpdate syncs the checkmark with the in-page switcher
        for (title, id, key) in [("Glass", "glass", "1"), ("Terminal", "terminal", "2")] {
            let item = NSMenuItem(title: title, action: #selector(setTheme(_:)), keyEquivalent: key)
            item.representedObject = id
            view.addItem(item)
        }
        viewItem.submenu = view

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(.separator())
        win.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = win
        NSApp.windowsMenu = win

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Backspacer on GitHub", action: #selector(openRepo(_:)), keyEquivalent: "?")
        help.addItem(withTitle: "Report a Problem…", action: #selector(openIssues(_:)), keyEquivalent: "")
        help.addItem(withTitle: "Reveal Diagnostics Log", action: #selector(revealLog(_:)), keyEquivalent: "")
        helpItem.submenu = help
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }
}
