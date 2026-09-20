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
    private let tildeHome: String
    private let defaults: UserDefaults
    private let pathPrefix: String?
    private let trasher: (URL) throws -> Void
    private let shell: CommandRunner
    private let diagnostics: Diagnostics
    private let fm = FileManager.default

    enum Disposal { case permanent, trash }

    /// `home` (the safety gate's notion of the home folder), `tildeHome` (what a leading `~` in
    /// the catalog expands to) and `defaults` are injectable so tests run against a throwaway
    /// directory and an isolated preferences suite.
    init(catalog: Catalog,
         home: String = FileManager.default.homeDirectoryForCurrentUser.path,
         tildeHome: String = FileManager.default.homeDirectoryForCurrentUser.path,
         defaults: UserDefaults = .standard,
         pathPrefix: String? = nil,
         trasher: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
         shell: CommandRunner = SystemShell(),
         diagnostics: Diagnostics = .standard) {
        self.catalog = catalog
        self.home = home
        self.tildeHome = tildeHome
        self.defaults = defaults
        self.pathPrefix = pathPrefix
        self.trasher = trasher
        self.shell = shell
        self.diagnostics = diagnostics
    }

    func catalogEntry(_ id: String) -> Catalog.Entry? { catalog.entry(id) }

    /// Your-call items are real data, so they go to the Trash (Finder can put them back).
    /// Caches are removed for good — parked in the Trash they'd reclaim nothing. Admin paths
    /// and command-driven entries can't be trashed.
    func disposal(of e: Catalog.Entry) -> Disposal {
        e.bucket == "decide" && !e.needsAdmin && e.deleteCmd == nil && e.itemsCmd == nil ? .trash : .permanent
    }

    /// True for a symbolic link itself (lstat, not what it points to).
    private func isSymlink(_ path: String) -> Bool {
        (try? fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// Removes paths according to the entry's disposal. Trashing that fails is an error, never a
    /// fallback to rm. Symlinks are never targets: a link's destination isn't what the catalog
    /// described, and `rm -rf link/` would follow it (R9).
    private func remove(_ paths: [String], for e: Catalog.Entry) throws -> Bool {
        for p in paths where isSymlink(p) { throw BridgeError.failed("Refused: \(p) is a symbolic link.") }
        switch disposal(of: e) {
        case .trash:
            for p in paths { diagnostics.log(.info, "trash: " + p); try trasher(URL(fileURLWithPath: p)) }
            return true
        case .permanent:
            let cmd = "rm -rf " + paths.map(Shell.q).joined(separator: " ")
            diagnostics.log(.info, (e.needsAdmin ? "admin: " : "run: ") + cmd)
            let r = e.needsAdmin ? shell.runAsAdmin(cmd) : shell.run(cmd, timeout: 1800, login: false)
            guard r.ok else { throw BridgeError.failed(r.stderr.isEmpty ? "exit status \(r.status)" : r.stderr) }
            return false
        }
    }

    /// Runs a command the catalog defines (sizeCmd, infoCmd, deleteCmd, itemsCmd, deleteItemCmd) —
    /// always as the user. Admin work is never a catalog command: the only thing that runs as
    /// root is an `rm -rf` the bridge builds itself from gate-checked paths (R7).
    /// `pathPrefix` lets tests put fake tools (brew, xcrun) first on PATH.
    /// Where the tools catalog commands need usually live. Appended *after* the user's PATH, so
    /// this is a fallback for shells whose profile doesn't set PATH the way Terminal does
    /// (`.zshrc`-only setups, bash, fish) — never a way to shadow the user's own choice (R6).
    private var toolFallbackPath: String {
        ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/share/dotnet",
         tildeHome + "/.dotnet/tools", tildeHome + "/.cargo/bin", tildeHome + "/.bun/bin", tildeHome + "/.pub-cache/bin", tildeHome + "/.local/bin"]
            .map(Shell.q).joined(separator: ":")
    }

    private func runCatalogCommand(_ cmd: String, timeout: TimeInterval) -> ShellResult {
        let head = pathPrefix.map { Shell.q($0) + ":" } ?? ""
        let full = "export PATH=\(head)$PATH:\(toolFallbackPath); " + cmd
        let r = shell.run(full, timeout: timeout, login: true)
        if !r.ok { diagnostics.log(.warn, "command failed (\(r.status)): \(cmd.prefix(200)) — \(r.stderr.prefix(300))") }
        return r
    }

    private func expand(_ p: String) -> String {
        p == "~" ? tildeHome : p.hasPrefix("~/") ? tildeHome + p.dropFirst() : p
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

    /// Ops too frequent or too dull to log.
    private static let quietOps: Set<String> = ["catalog", "disk", "fdaStatus", "prefGet", "prefSet", "projectRoots", "appInfo", "log", "logPath", "scanHints"]

    // MARK: Scan hints — how long each entry took last time, so the page can start the slow ones first.

    private static let durationsKey = "scan.durations"
    private let durationsLock = NSLock()

    private func rememberDuration(_ id: String, _ ms: Int) {
        durationsLock.lock(); defer { durationsLock.unlock() }
        var d = defaults.dictionary(forKey: Self.durationsKey) as? [String: Int] ?? [:]
        d[id] = ms
        defaults.set(d, forKey: Self.durationsKey)
    }

    func handle(op: String, args: [String: Any]) throws -> Any {
        let started = Date()
        let subject = (args["id"] as? String).map { $0 + ((args["item"] as? String).map { " · " + $0 } ?? "") } ?? ""
        do {
            let r = try dispatch(op: op, args: args)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if !Self.quietOps.contains(op) {
                diagnostics.log(.info, "\(op) \(subject) ok (\(ms) ms)".replacingOccurrences(of: "  ", with: " "))
            }
            if op == "size", let id = args["id"] as? String { rememberDuration(id, ms) }
            return r
        } catch {
            diagnostics.log(.error, "\(op) \(subject): \(error.localizedDescription)".replacingOccurrences(of: "  ", with: " "))
            throw error
        }
    }

    private func dispatch(op: String, args: [String: Any]) throws -> Any {
        switch op {
        case "catalog":   return RawJSON(value: catalog.rawJSON)
        case "disk":      return try disk()
        case "fdaStatus": return ["granted": hasFullDiskAccess()]
        case "openFDA":   openFullDiskAccessSettings(); return ["ok": true]
        case "size":      return try size(entry(args))
        case "info":      return try info(entry(args))
        case "delete":    return try delete(entry(args), item: args["item"] as? String)
        case "reveal":    return try reveal(entry(args))
        case "appInfo":   return ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "dev",
                                  "build": Bundle.main.infoDictionary?["CFBundleVersion"] ?? "local"]
        case "prefGet":   return ["value": defaults.string(forKey: try prefKey(args)).map { $0 as Any } ?? NSNull()]
        case "prefSet":   defaults.set(try prefValue(args), forKey: try prefKey(args)); return ["ok": true]
        case "projectRoots":      return rootsReply()
        case "addProjectRoot":    if let p = chooseFolder() { try addProjectRoot(path: p) }; return rootsReply()
        case "removeProjectRoot": try removeProjectRoot(path: args["path"] as? String ?? ""); return rootsReply()
        case "log":
            let level = Diagnostics.Level(rawValue: args["level"] as? String ?? "") ?? .info
            diagnostics.log(level, "page: " + String((args["message"] as? String ?? "").prefix(2000)))
            return ["ok": true]
        case "logPath":  return ["path": diagnostics.file.path]
        case "scanHints": return ["durations": defaults.dictionary(forKey: Self.durationsKey) as? [String: Int] ?? [:]]
        case "revealLog":
            diagnostics.log(.info, "revealing the log file")
            let url = diagnostics.file
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            return ["path": url.path]
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

    // MARK: Project folders — where `"root": "$PROJECTS"` globs look.

    private static let rootsKey = "ui.projectRoots"
    /// Tried in this order when the user hasn't chosen anything.
    static let candidateRoots = ["~/Projects", "~/Developer", "~/code", "~/src", "~/dev", "~/work",
                                 "~/repos", "~/git", "~/Documents/GitHub", "~/Sites"]

    func projectRoots() -> [String] {
        if let stored = defaults.stringArray(forKey: Self.rootsKey) { return stored.filter(isValidProjectRoot) }
        return Self.candidateRoots.map(expand).filter(isValidProjectRoot)
    }

    /// A directory inside home, but not home itself and nothing under ~/Library — a glob rooted
    /// there would reach app data the catalog never meant to expose.
    func isValidProjectRoot(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        guard p.hasPrefix(home + "/"), p != home + "/Library", !p.hasPrefix(home + "/Library/") else { return false }
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
    }

    func addProjectRoot(path: String) throws {
        let p = (path as NSString).standardizingPath
        guard isValidProjectRoot(p) else { throw BridgeError.failed("Choose a folder inside your home folder (not ~/Library).") }
        var roots = projectRoots()
        if !roots.contains(p) { roots.append(p) }
        defaults.set(roots, forKey: Self.rootsKey)
    }

    func removeProjectRoot(path: String) throws {
        let p = (path as NSString).standardizingPath
        var roots = projectRoots()
        guard let i = roots.firstIndex(of: p) else { throw BridgeError.failed("Not a project folder: \(path)") }
        roots.remove(at: i)
        defaults.set(roots, forKey: Self.rootsKey)
    }

    private func rootsReply() -> [String: Any] {
        ["roots": projectRoots().map { ["path": $0, "display": $0.hasPrefix(tildeHome + "/") ? "~" + $0.dropFirst(tildeHome.count) : $0] }]
    }

    /// The system folder picker, on the main thread. The chosen path comes from the user via
    /// macOS, never from the page.
    private func chooseFolder() -> String? {
        var chosen: String?
        let pick = {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: self.home)
            panel.message = "Choose a folder that holds your projects. Build output inside it (node_modules, Pods, …) becomes reclaimable."
            panel.prompt = "Add"
            if panel.runModal() == .OK { chosen = panel.url?.path }
        }
        if Thread.isMainThread { pick() } else { DispatchQueue.main.sync(execute: pick) }
        return chosen
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
        (try? fm.contentsOfDirectory(atPath: tildeHome + "/Library/Safari")) != nil
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }

    private func size(_ e: Catalog.Entry) throws -> [String: Any] {
        // Behind Full Disk Access a du would silently report 0 and the row would vanish below the
        // threshold; unknown is the honest answer, and the page says what it takes.
        if e.fda == true && !hasFullDiskAccess() { return ["bytes": NSNull(), "paths": [String](), "fda": true] }
        if let cmd = e.sizeCmd {
            let r = runCatalogCommand(cmd, timeout: 300)
            if let kb = parseKB(r.stdout) { return ["bytes": kb * 1024, "paths": [String]()] }
            return ["bytes": NSNull(), "paths": [String]()]
        }
        if let cmd = e.itemsCmd {
            // Command-listed items (simulators, runtimes). Total is du of the path when there is
            // one, otherwise the sum of the items.
            let items = Self.parseItems(runCatalogCommand(cmd, timeout: 300).stdout).sorted { $0.kb > $1.kb }
            let reply: [String: Any] = ["items": items.map { ["key": $0.key, "label": $0.label, "bytes": $0.kb * 1024] }, "paths": resolvePaths(e)]
            let paths = resolvePaths(e)
            if paths.isEmpty {
                return reply.merging(["bytes": items.reduce(Int64(0)) { $0 + $1.kb * 1024 }]) { $1 }
            }
            let r = shell.run("du -skxc " + paths.map(Shell.q).joined(separator: " ") + " 2>/dev/null", timeout: 600, login: false)
            let total = Int64(r.stdout.split(separator: "\n").last.map { parseKB(String($0)) ?? 0 } ?? 0) * 1024
            return reply.merging(["bytes": total]) { $1 }
        }
        let hasSource = e.path != nil || e.paths != nil || e.glob != nil
        let paths = resolvePaths(e)
        guard !paths.isEmpty else {
            let bytes: Any = hasSource ? Int64(0) : NSNull()
            return ["bytes": bytes, "paths": [String]()]
        }
        // One path: plain du. Several (glob matches, path lists): two dus at a time — du is
        // I/O-bound, and node_modules across a dozen projects was a 16-second serial measure.
        // Two, not more: with four scan workers that's at most eight dus on the user's machine.
        let perPath: [(path: String, kb: Int64)]
        let total: Int64
        if paths.count == 1 {
            let r = shell.run("du -skxc " + Shell.q(paths[0]) + " 2>/dev/null", timeout: 600, login: false)
            total = Int64(r.stdout.split(separator: "\n").last.map { parseKB(String($0)) ?? 0 } ?? 0) * 1024
            perPath = Self.parseDu(r.stdout)
        } else {
            perPath = Self.parseDu(parallelDu(paths))
            total = perPath.reduce(0) { $0 + $1.kb } * 1024
        }
        var reply: [String: Any] = ["bytes": total, "paths": paths]
        if e.isGranular {
            // children need their own pass over the subfolders; glob/paths already have one line per path.
            let lines = e.children == true ? parallelDu(resolveItems(e)) : nil
            let items = (lines.map(Self.parseDu) ?? perPath).sorted { $0.kb > $1.kb }
            reply["items"] = items.map { ["path": $0.path, "bytes": $0.kb * 1024, "display": display(of: $0.path, in: e)] }
            // With exclusions the parent's du would count what we never touch.
            if !(e.exclude ?? []).isEmpty { reply["bytes"] = items.reduce(Int64(0)) { $0 + $1.kb * 1024 } }
        }
        return reply
    }

    /// `du -skx` of each path, two at a time; one `KB<TAB>path` line per path (no total line).
    private func parallelDu(_ paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        let cmd = "printf '%s\\0' " + paths.map(Shell.q).joined(separator: " ") + " | xargs -0 -P 2 -n 1 du -skx 2>/dev/null"
        return shell.run(cmd, timeout: 600, login: false).stdout
    }

    /// How an item is named in the Details list: a glob match relative to the project folder it
    /// was found in, a child by its label file or its name, a listed path with home as `~`.
    private func display(of path: String, in e: Catalog.Entry) -> String {
        if let g = e.glob {
            let roots = g.root == "$PROJECTS" ? projectRoots() : [expand(g.root)]
            if let root = roots.first(where: { path.hasPrefix($0 + "/") }) { return String(path.dropFirst(root.count + 1)) }
        }
        if e.children == true {
            if let lbl = e.childLabel, let label = childLabel(of: path, lbl) { return label }
            let name = (path as NSString).lastPathComponent
            return e.companion != nil ? (name as NSString).deletingPathExtension : name
        }
        return abbreviate(path)
    }

    /// Reads `<child>/<file>` as JSON or (by extension) a property list and returns the first
    /// present key, with file:// URLs turned into paths and home shown as `~`.
    private func childLabel(of child: String, _ lbl: Catalog.ChildLabel) -> String? {
        guard let data = fm.contents(atPath: child + "/" + lbl.file) else { return nil }
        let dict: [String: Any]?
        if lbl.file.hasSuffix(".plist") {
            dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        } else {
            dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let json = dict else { return nil }
        for key in lbl.keys {
            guard let raw = json[key] as? String else { continue }
            let path = raw.hasPrefix("file://") ? (URL(string: raw)?.path ?? raw) : raw
            return abbreviate(path)
        }
        return nil
    }

    private func abbreviate(_ path: String) -> String {
        path.hasPrefix(tildeHome + "/") ? "~" + path.dropFirst(tildeHome.count) : path
    }

    /// `itemsCmd` output → (key, label, KB) per line; anything not three tab-separated fields is skipped.
    static func parseItems(_ out: String) -> [(key: String, label: String, kb: Int64)] {
        out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 3, let kb = Int64(f[2].trimmingCharacters(in: .whitespaces)), !f[0].isEmpty else { return nil }
            return (String(f[0]), String(f[1]), kb)
        }
    }

    /// `du -sk` output → (path, KB) per line; the `total` line from `-c` is dropped.
    static func parseDu(_ out: String) -> [(path: String, kb: Int64)] {
        out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kb = Int64(parts[0]), parts[1] != "total" else { return nil }
            return (String(parts[1]), kb)
        }
    }

    private func fmt(_ bytes: Int64) -> String {
        bytes < 1_000_000 ? "\(bytes / 1000) KB" : bytes < 1_000_000_000 ? "\(bytes / 1_000_000) MB" : String(format: "%.1f GB", Double(bytes) / 1e9)
    }

    private func info(_ e: Catalog.Entry) throws -> [String: Any] {
        if let cmd = e.infoCmd {
            let r = runCatalogCommand(cmd, timeout: 120)
            return ["text": String(r.combined.prefix(20_000))]
        }
        // No command: show what's inside, largest first.
        guard let p = resolvePaths(e).first else { return ["text": ""] }
        // In sh an unmatched glob stays literal and du just complains to /dev/null.
        let r = shell.run("du -skx \(Shell.q(p))/* \(Shell.q(p))/.[!.]* 2>/dev/null | sort -rn | head -40", timeout: 300, login: false)
        let lines = Self.parseDu(r.stdout).map { item -> String in
            let name = (item.path as NSString).lastPathComponent
            return fmt(item.kb * 1024).padding(toLength: 9, withPad: " ", startingAt: 0) + "  " + name
        }
        return ["text": lines.joined(separator: "\n")]
    }

    private func delete(_ e: Catalog.Entry, item: String? = nil) throws -> [String: Any] {
        if let item, e.itemsCmd != nil { return try deleteCommandItem(e, key: item) }
        guard e.isDeletable else { throw BridgeError.notDeletable(e.label) }
        if let item { return try deleteItem(e, item) }
        let before = ((try? size(e))?["bytes"] as? Int64) ?? 0

        if let custom = e.deleteCmd {
            guard !e.needsAdmin else { throw BridgeError.failed("\(e.label): admin entries can't run commands.") }
            let r = runCatalogCommand(custom, timeout: 1800)
            guard r.ok else { throw BridgeError.failed(r.stderr.isEmpty ? "exit status \(r.status)" : r.stderr) }
            return ["ok": true, "freedBytes": before]
        }
        // A children entry with exclusions is swept child by child so the excluded ones stay.
        let paths = (e.exclude ?? []).isEmpty ? resolvePaths(e) : resolveItems(e)
        guard !paths.isEmpty else { return ["ok": true, "freedBytes": 0] }
        for p in paths where !isSafeToDelete(p) { throw BridgeError.unsafePath(p) }
        let trashed = try remove(paths, for: e)
        return trashed ? ["ok": true, "freedBytes": before, "trashed": true] : ["ok": true, "freedBytes": before]
    }

    /// One command-listed item. `key` is a selector: it must appear in a fresh run of itemsCmd,
    /// and it is shell-quoted before substitution — the page never composes a command.
    private func deleteCommandItem(_ e: Catalog.Entry, key: String) throws -> [String: Any] {
        guard e.canDeleteItems, let listCmd = e.itemsCmd, let template = e.deleteItemCmd else { throw BridgeError.notDeletable(e.label) }
        guard !e.needsAdmin else { throw BridgeError.failed("\(e.label): admin entries can't run commands.") }
        let items = Self.parseItems(runCatalogCommand(listCmd, timeout: 300).stdout)
        guard let item = items.first(where: { $0.key == key }) else { throw BridgeError.failed("Not one of \(e.label)'s items: \(key)") }
        let command = template.replacingOccurrences(of: "{key}", with: Shell.q(key))
        let r = runCatalogCommand(command, timeout: 1800)
        guard r.ok else { throw BridgeError.failed(r.stderr.isEmpty ? "exit status \(r.status)" : r.stderr) }
        return ["ok": true, "freedBytes": item.kb * 1024]
    }

    /// One item of a granular entry. `item` is only a selector: it must be in the entry's
    /// freshly resolved item set, so the web layer still can't name a path the catalog doesn't.
    private func deleteItem(_ e: Catalog.Entry, _ item: String) throws -> [String: Any] {
        guard e.deleteCmd == nil else { throw BridgeError.failed("\(e.label) is removed by a command, not per item.") }
        guard resolveItems(e).contains(item) else { throw BridgeError.failed("Not one of \(e.label)'s items: \(item)") }
        guard isSafeToDelete(item) else { throw BridgeError.unsafePath(item) }
        // A companion file (an AVD's .ini next to its .avd folder) goes with the child.
        var targets = [item]
        if let ext = e.companion {
            let companion = (item as NSString).deletingPathExtension + ext
            if fm.fileExists(atPath: companion) || isSymlink(companion) {
                guard isSafeToDelete(companion) else { throw BridgeError.unsafePath(companion) }
                targets.append(companion)
            }
        }
        let before = (Self.parseDu(shell.run("du -skx \(Shell.q(item)) 2>/dev/null", timeout: 600, login: false).stdout).first?.kb ?? 0) * 1024
        let trashed = try remove(targets, for: e)
        return trashed ? ["ok": true, "freedBytes": before, "trashed": true] : ["ok": true, "freedBytes": before]
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
        if let p = e.path { out.append(expand(p)) }
        if let ps = e.paths { out += ps.map(expand) }
        if let g = e.glob { out += globMatches(g) }
        // Root-only paths may not be stat-able as the user; keep them for admin entries.
        return e.needsAdmin ? out : out.filter { fm.fileExists(atPath: $0) }
    }

    /// The individually actionable paths of a granular entry: glob matches, the listed
    /// paths, or (children: true) each path's immediate subfolders.
    private func resolveItems(_ e: Catalog.Entry) -> [String] {
        let paths = resolvePaths(e)
        guard e.children == true else { return paths }
        let excluded = Set(e.exclude ?? [])
        return paths.flatMap { p -> [String] in
            let names = (try? fm.contentsOfDirectory(atPath: p)) ?? []
            return names.sorted().filter { !excluded.contains($0) }.map { p + "/" + $0 }
                .filter { var d: ObjCBool = false; return fm.fileExists(atPath: $0, isDirectory: &d) && d.boolValue }
        }
    }

    private func globMatches(_ g: Catalog.Glob) -> [String] {
        let roots = g.root == "$PROJECTS" ? projectRoots() : [expand(g.root)]
        var paths = roots.flatMap { globMatches(g, root: $0) }

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

    private func globMatches(_ g: Catalog.Glob, root: String) -> [String] {
        var tests: [String] = []
        if let n = g.name { tests.append("-name \(Shell.q(n))") }
        if let ns = g.names { tests += ns.map { "-name \(Shell.q($0))" } }
        if let pp = g.pathPatterns { tests += pp.map { "-path \(Shell.q(root + "/" + $0))" } }
        guard !tests.isEmpty else { return [] }

        var cmd = "find \(Shell.q(root)) -maxdepth \(g.maxdepth ?? 4)"
        if let t = g.type { cmd += " -type \(t)" }
        cmd += " \\( " + tests.joined(separator: " -o ") + " \\) -prune -print0 2>/dev/null"
        return shell.run(cmd, timeout: 300, login: false).stdout.split(separator: "\0").map(String.init)
    }

    /// Last line of defence. Even though paths come from the catalog, refuse
    /// anything that could take a user's data with it.
    /// User data the catalog must never be able to reach, even below depth 2. Relative to home.
    static let userDataRoots = [
        "Documents", "Desktop", "Pictures", "Movies", "Music", "Public",
        "Library/Mail", "Library/Messages", "Library/Keychains", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Group Containers", "Library/Accounts", "Library/Cookies", "Library/Safari",
        ".ssh", ".gnupg",
    ]

    func isSafeToDelete(_ path: String) -> Bool {
        let given = (path as NSString).standardizingPath
        guard given.hasPrefix("/"), !given.contains("/../"), given != "/" else { return false }
        // Symlinks are resolved so a link inside an allowed folder can't point at user data;
        // both spellings must pass. Comparisons fold case: the default file system does.
        let resolved = URL(fileURLWithPath: given).resolvingSymlinksInPath().path
        return [given, resolved].allSatisfy(passesGate)
    }

    private func passesGate(_ p: String) -> Bool {
        let home = self.home.lowercased()
        let lp = p.lowercased()
        func under(_ root: String) -> Bool { lp == root || lp.hasPrefix(root + "/") }
        func within(_ root: String) -> Bool { lp.hasPrefix(root + "/") }

        let forbidden = [
            home, home + "/library", home + "/projects", home + "/downloads",
            home + "/library/application support", home + "/library/developer", home + "/library/containers",
            "/users", "/library", "/system", "/applications", "/private", "/private/var", "/opt",
        ]
        if forbidden.contains(lp) { return false }

        // Only these roots at all, and only below them (a root needs its separator: "…Data-2" is not
        // "…Data/"). The staged-update folder is the one root that is itself the thing to delete.
        guard within(home) || within("/library/developer") || under("/system/volumes/data/macos install data") else { return false }

        if within(home) {
            let rel = lp.dropFirst(home.count + 1)
            // Top-level visible folders in home are never deletable; dot-folders (~/.cache) are.
            if rel.split(separator: "/").count < 2 && !rel.hasPrefix(".") { return false }
            // Photos libraries, wherever they are.
            if lp.contains(".photoslibrary/") || lp.hasSuffix(".photoslibrary") { return false }
            // User data — unless the user pointed a project folder there, in which case what
            // the globs find inside it (node_modules, Pods, build/) is theirs to reclaim.
            let insideProjectRoot = projectRoots().map { $0.lowercased() }.contains(where: within)
            if !insideProjectRoot && Self.userDataRoots.contains(where: { under(home + "/" + $0.lowercased()) }) { return false }
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
