import Testing
import AppKit
@testable import Backspacer

// X-tests: the page's right-click menu is WebKit's stock menu trimmed to what the app can use.
@Suite @MainActor struct ContextMenuTests {
    private func item(_ id: String?, _ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let id { i.identifier = NSUserInterfaceItemIdentifier(id) }
        return i
    }

    @Test("X1 only Search, Copy (and Inspect Element) survive WebKit's text menu")
    func trimsTextMenu() {
        let items = [
            item("WKMenuItemIdentifierLookUp", "Look Up “codex”"), item("WKMenuItemIdentifierTranslate", "Translate “codex”"),
            item("WKMenuItemIdentifierSearchWeb", "Search with Google"), item(nil, ""),
            item("WKMenuItemIdentifierCopy", "Copy"), item("WKMenuItemIdentifierCopyLinkWithHighlight", "Copy Link with Highlight"),
            item("WKMenuItemIdentifierShareMenu", "Share…"), item("WKMenuItemIdentifierWritingTools", "Show Writing Tools"),
            item("WKMenuItemIdentifierSpeechMenu", "Speech"), item(nil, "Services"),   // AppKit appends this after the trim; it goes with the rest
            item("WKMenuItemIdentifierInspectElement", "Inspect Element"),
        ]
        #expect(PageView.trim(items).map(\.title) == ["Search with Google", "Copy", "Inspect Element"])
    }

    @Test("X2 the page-background menu (Reload, Back…) is dropped entirely")
    func dropsPageMenu() {
        let items = [item("WKMenuItemIdentifierGoBack", "Back"), item("WKMenuItemIdentifierGoForward", "Forward"), item("WKMenuItemIdentifierReload", "Reload")]
        #expect(PageView.trim(items).isEmpty)
    }
}

@Suite @MainActor struct PathMenuTests {
    @Test("X5 path items appear only for a fresh right-click target and carry its selector")
    func pathItems() {
        let target = PageView.ContextTarget(id: "c", item: "/x/18.0", at: Date())
        let items = PageView.pathItems(for: target, now: Date())
        #expect(items.map(\.title) == ["New Terminal at Folder"], "Reveal already covers Finder")
        #expect(items.allSatisfy { ($0.representedObject as? PageView.ContextTarget)?.id == "c" })
        let stale = PageView.ContextTarget(id: "c", item: nil, at: Date(timeIntervalSinceNow: -5))
        #expect(PageView.pathItems(for: stale, now: Date()).isEmpty, "a target from an earlier click never leaks into a later menu")
        #expect(PageView.pathItems(for: nil, now: Date()).isEmpty)
    }
}
