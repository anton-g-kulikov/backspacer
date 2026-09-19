import AppKit
import WebKit

/// The only door between the web UI and the machine.
///
/// The UI sends `{id, op, args}`; every op that touches the disk takes a
/// catalog entry *id*, never a path. Paths are resolved here from the bundled
/// catalog.json, so a compromised or buggy web layer cannot name a path.
/// Replies go back as `window.__reclaimerReply(id, ok, payload)`.
final class Bridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "reclaimer"

    weak var webView: WKWebView?
    private let catalog: Catalog
    private let queue = DispatchQueue(label: "reclaimer.bridge", qos: .userInitiated, attributes: .concurrent)
    private let home: String
    private let fm = FileManager.default

    /// `home` is injectable so the safety gate can be tested against a fixed path.
    init(catalog: Catalog, home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.catalog = catalog
        self.home = home
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let op = body["op"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let payload = try self.handle(op: op, args: args)
                self.reply(id, ok: true, payload: payload)
            } catch {
                self.reply(id, ok: false, payload: ["error": error.localizedDescription])
            }
        }
    }

    private struct RawJSON { let value: String }

    private func reply(_ id: Int, ok: Bool, payload: Any) {
        let json: String
        if let raw = payload as? RawJSON {
            json = raw.value
        } else if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            json = String(decoding: data, as: UTF8.self)
        } else {
            json = #"{"error":"unserializable reply"}"#
        }
        let js = "window.__reclaimerReply(\(id), \(ok), \(json));"
        DispatchQueue.main.async { self.webView?.evaluateJavaScript(js, completionHandler: nil) }
    }

    // MARK: Dispatch

    private func handle(op: String, args: [String: Any]) throws -> Any {
        switch op {
        case "catalog":   return RawJSON(value: catalog.rawJSON)
        case "disk":      return try disk()
        case "fdaStatus": return ["granted": hasFullDiskAccess()]
        case "openFDA":   openFullDiskAccessSettings(); return ["ok": true]
        case "size":      return try size(entry(args))
        case "info":      return try info(entry(args))
        case "delete":    return try delete(entry(args))
        case "reveal":    return try reveal(entry(args))
        case "appInfo":   return ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "dev",
                                  "build": Bundle.main.infoDictionary?["CFBundleVersion"] ?? "local"]
        case "prefGet":   return ["value": UserDefaults.standard.string(forKey: try prefKey(args)).map { $0 as Any } ?? NSNull()]
        case "prefSet":   UserDefaults.standard.set(try prefValue(args), forKey: try prefKey(args)); return ["ok": true]
        default:          throw BridgeError.unknownOp(op)
        }
    }

    private func entry(_ args: [String: Any]) throws -> Catalog.Entry {
        guard let id = args["id"] as? String, let e = catalog.entry(id) else {
            throw BridgeError.unknownEntry(args["id"] as? String ?? "?")
        }
        return e
    }

    // MARK: Prefs — UI settings that should survive relaunch (the arm switch deliberately doesn't).

    private static let prefKeys: Set<String> = ["theme", "minSize"]

    func prefKey(_ args: [String: Any]) throws -> String {
        guard let k = args["key"] as? String, Self.prefKeys.contains(k) else {
            throw BridgeError.failed("Unknown preference: \(args["key"] ?? "?")")
        }
        return "ui." + k
    }

    func prefValue(_ args: [String: Any]) throws -> String {
        guard let v = args["value"] as? String, v.count <= 32 else { throw BridgeError.failed("Bad preference value") }
        return v
    }

    // MARK: Ops

    private func disk() throws -> [String: Any] {
        let url = URL(fileURLWithPath: home)
        let v = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(v.volumeTotalCapacity ?? 0)
        let free = v.volumeAvailableCapacityForImportantUsage ?? 0   // matches Finder: includes purgeable space
        return ["size": total, "free": free, "used": total - free]
    }

    /// ~/Library/Safari is TCC-protected; listing it succeeds only with Full Disk Access.
    private func hasFullDiskAccess() -> Bool {
        (try? fm.contentsOfDirectory(atPath: home + "/Library/Safari")) != nil
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }

    private func size(_ e: Catalog.Entry) throws -> [String: Any] {
        if let cmd = e.sizeCmd {
            let r = Shell.run(cmd, timeout: 300)
            if let kb = parseKB(r.stdout) { return ["bytes": kb * 1024, "paths": [String]()] }
            return ["bytes": NSNull(), "paths": [String]()]
        }
        let hasSource = e.path != nil || e.paths != nil || e.glob != nil
        let paths = resolvePaths(e)
        guard !paths.isEmpty else {
            let bytes: Any = hasSource ? Int64(0) : NSNull()
            return ["bytes": bytes, "paths": [String]()]
        }
        let r = Shell.run("du -skxc " + paths.map(Shell.q).joined(separator: " ") + " 2>/dev/null | tail -1", timeout: 600)
        let kb = parseKB(r.stdout) ?? 0
        return ["bytes": kb * 1024, "paths": paths]
    }

    private func info(_ e: Catalog.Entry) throws -> [String: Any] {
        guard let cmd = e.infoCmd else { return ["text": ""] }
        let r = Shell.run(cmd, timeout: 120)
        return ["text": String(r.combined.prefix(20_000))]
    }

    private func delete(_ e: Catalog.Entry) throws -> [String: Any] {
        guard e.isDeletable else { throw BridgeError.notDeletable(e.label) }
        let before = ((try? size(e))?["bytes"] as? Int64) ?? 0

        let command: String
        if let custom = e.deleteCmd {
            command = custom
        } else {
            let paths = resolvePaths(e)
            guard !paths.isEmpty else { return ["ok": true, "freedBytes": 0] }
            for p in paths where !isSafeToDelete(p) { throw BridgeError.unsafePath(p) }
            command = "rm -rf " + paths.map(Shell.q).joined(separator: " ")
        }

        let r = e.needsAdmin ? Shell.runAsAdmin(command) : Shell.run(command, timeout: 1800)
        guard r.ok else { throw BridgeError.failed(r.stderr.isEmpty ? "exit status \(r.status)" : r.stderr) }
        return ["ok": true, "freedBytes": before]
    }

    private func reveal(_ e: Catalog.Entry) throws -> [String: Any] {
        guard let first = resolvePaths(e).first else { throw BridgeError.failed("Nothing there to show.") }
        let url = URL(fileURLWithPath: first)
        DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        return ["ok": true]
    }

    // MARK: Path resolution

    private func resolvePaths(_ e: Catalog.Entry) -> [String] {
        var out: [String] = []
        if let p = e.path { out.append(p.expandingTilde) }
        if let ps = e.paths { out += ps.map { $0.expandingTilde } }
        if let g = e.glob { out += globMatches(g) }
        // Root-only paths may not be stat-able as the user; keep them for admin entries.
        return e.needsAdmin ? out : out.filter { fm.fileExists(atPath: $0) }
    }

    private func globMatches(_ g: Catalog.Glob) -> [String] {
        let root = g.root.expandingTilde
        var tests: [String] = []
        if let n = g.name { tests.append("-name \(Shell.q(n))") }
        if let ns = g.names { tests += ns.map { "-name \(Shell.q($0))" } }
        if let pp = g.pathPatterns { tests += pp.map { "-path \(Shell.q(root + "/" + $0))" } }
        guard !tests.isEmpty else { return [] }

        var cmd = "find \(Shell.q(root)) -maxdepth \(g.maxdepth ?? 4)"
        if let t = g.type { cmd += " -type \(t)" }
        cmd += " \\( " + tests.joined(separator: " -o ") + " \\) -prune -print0 2>/dev/null"

        var paths = Shell.run(cmd, timeout: 300).stdout.split(separator: "\0").map(String.init)

        if let sibling = g.requireSibling {
            let suffix = sibling.hasPrefix("*") ? String(sibling.dropFirst()) : sibling
            paths = paths.filter { p in
                let parent = (p as NSString).deletingLastPathComponent
                let items = (try? fm.contentsOfDirectory(atPath: parent)) ?? []
                return items.contains { $0.hasSuffix(suffix) }
            }
        }
        if let then = g.then {
            paths = paths.map { $0 + "/" + then }.filter { fm.fileExists(atPath: $0) }
        }
        return paths
    }

    /// Last line of defence. Even though paths come from the catalog, refuse
    /// anything that could take a user's data with it.
    func isSafeToDelete(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        guard p.hasPrefix("/"), !p.contains("/../"), p != "/" else { return false }

        let forbidden: Set<String> = [
            home, home + "/Library", home + "/Projects", home + "/Documents", home + "/Desktop",
            home + "/Downloads", home + "/Pictures", home + "/Movies", home + "/Music",
            home + "/Library/Application Support", home + "/Library/Developer", home + "/Library/Containers",
            "/Users", "/Library", "/System", "/Applications", "/private", "/private/var", "/opt",
        ]
        if forbidden.contains(p) { return false }

        let allowedRoots = [home + "/", "/Library/Developer/", "/System/Volumes/Data/macOS Install Data"]
        guard allowedRoots.contains(where: { p.hasPrefix($0) }) else { return false }

        if p.hasPrefix(home + "/") {
            let rel = p.dropFirst(home.count + 1)
            let depth = rel.split(separator: "/").count
            // Top-level visible folders in home are never deletable; dot-folders (~/.cache) are.
            if depth < 2 && !rel.hasPrefix(".") { return false }
        }
        return true
    }

    private func parseKB(_ s: String) -> Int64? {
        let token = s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.map(String.init) ?? ""
        return Int64(token)
    }
}

enum BridgeError: LocalizedError {
    case unknownOp(String), unknownEntry(String), notDeletable(String), unsafePath(String), failed(String)
    var errorDescription: String? {
        switch self {
        case .unknownOp(let op):      return "Unknown operation: \(op)"
        case .unknownEntry(let id):   return "Unknown catalog entry: \(id)"
        case .notDeletable(let l):    return "\(l) isn't deletable from Reclaimer."
        case .unsafePath(let p):      return "Refused to delete \(p) — outside the allowed roots."
        case .failed(let m):          return m
        }
    }
}
