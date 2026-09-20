import AppKit
import WebKit

/// The web view, with WebKit's context menu cut down to what the page can use. The stock menu on
/// selected text offers Look Up, Translate, web search, Share, Writing Tools, Speech and a Services
/// submenu that macOS fills for any text (Add to Music as a Spoken Track…) and that an app cannot
/// prune. Search and Copy stay (and Inspect Element when the inspector is on); the Services submenu
/// is replaced by the app's own action for the row or Details item under the pointer — New Terminal
/// at Folder (Reveal already covers Finder) — which the page names by selector on right-click and
/// the bridge resolves and validates. On the page
/// background, where WebKit offers Back/Forward/Reload, no menu appears at all.
final class PageView: WKWebView {
    private static let kept: Set<String> = ["WKMenuItemIdentifierSearchWeb", "WKMenuItemIdentifierCopy", "WKMenuItemIdentifierInspectElement"]

    /// What the page last right-clicked: an entry id and, inside Details, the item's selector.
    struct ContextTarget: Sendable { let id: String; let item: String?; let at: Date }
    var contextTarget: ContextTarget?
    var bridge: Bridge?

    static func trim(_ items: [NSMenuItem]) -> [NSMenuItem] {
        items.filter { item in item.identifier.map { kept.contains($0.rawValue) } ?? false }
    }

    /// Path actions for a target the page reported for *this* click (a stale one is never reused).
    static func pathItems(for target: ContextTarget?, now: Date) -> [NSMenuItem] {
        guard let target, now.timeIntervalSince(target.at) < 2 else { return [] }
        let item = NSMenuItem(title: "New Terminal at Folder", action: #selector(openInTerminal(_:)), keyEquivalent: "")
        item.representedObject = target
        return [item]
    }

    /// AppKit appends its Services submenu to the context menu of any view that vends selected
    /// text, after `willOpenMenu` — declining every service is the only way to keep it off.
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? { nil }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let survivors = Self.trim(menu.items)
        let paths = Self.pathItems(for: contextTarget, now: Date())
        contextTarget = nil
        menu.removeAllItems()
        for item in survivors { menu.addItem(item) }
        if !survivors.isEmpty, !paths.isEmpty { menu.addItem(.separator()) }
        for item in paths { item.target = self; menu.addItem(item) }
    }

    @objc private func openInTerminal(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? ContextTarget, let bridge else { return }
        var args: [String: Any] = ["id": target.id, "with": "terminal"]
        if let item = target.item { args["item"] = item }
        bridge.perform(op: "open", args: args)
    }
}
