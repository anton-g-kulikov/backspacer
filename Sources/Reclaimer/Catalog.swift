import Foundation

/// Mirror of catalog.json. The web UI gets the raw JSON; the bridge uses these
/// typed values so that every path it touches comes from the catalog, never
/// from the web layer.
struct Catalog: Decodable {
    struct Glob: Decodable {
        var root: String
        var name: String?
        var names: [String]?
        var pathPatterns: [String]?
        var maxdepth: Int?
        var type: String?
        var then: String?            // append this component to each match (e.g. ".next" → ".next/cache")
        var requireSibling: String?  // only keep matches whose parent contains a file matching this glob (e.g. "*.csproj")
    }

    /// For `children: true`: name each child after a value in a JSON file it contains.
    struct ChildLabel: Decodable {
        var file: String        // e.g. "workspace.json"
        var keys: [String]      // first present key wins, e.g. ["folder", "workspace"]
    }

    struct Entry: Decodable {
        var id: String
        var group: String
        var bucket: String
        var label: String
        var path: String?
        var paths: [String]?
        var glob: Glob?
        var children: Bool?          // list the path's immediate subfolders as individually deletable items
        var childLabel: ChildLabel?  // with children: label each subfolder from a JSON file inside it
        var exclude: [String]?       // with children: subfolder names never listed nor removed
        var companion: String?       // with children: a sibling file "<stem><companion>" removed with each child (AVD .ini)
        var fda: Bool?               // lives behind Full Disk Access: without it, size is unknown rather than 0
        var sudo: Bool?
        var manual: Bool?
        var note: String?
        var sizeCmd: String?
        var infoCmd: String?
        var deleteCmd: String?
        var itemsCmd: String?        // prints one item per line: key<TAB>label<TAB>KB
        var deleteItemCmd: String?   // removes one item; {key} is replaced with the quoted key

        var needsAdmin: Bool { sudo ?? false }
        var isManual: Bool { manual ?? false }
        /// Resolves to several items the user can act on one at a time.
        var isGranular: Bool { glob != nil || paths != nil || children == true || itemsCmd != nil }
        /// Items can be removed individually: by path (rm) or by command (deleteItemCmd).
        var canDeleteItems: Bool {
            ["safe", "regen", "decide"].contains(bucket) && !isManual
                && (deleteItemCmd != nil || (isDeletable && deleteCmd == nil && itemsCmd == nil))
        }
        var isDeletable: Bool {
            ["safe", "regen", "decide"].contains(bucket) && !isManual
                && (path != nil || paths != nil || glob != nil || deleteCmd != nil)
        }
    }

    var version: Int
    var entries: [Entry]
    var rawJSON: String = ""

    private enum CodingKeys: String, CodingKey { case version, entries }

    static func load() throws -> Catalog {
        guard let url = Resources.url("catalog.json") else {
            throw NSError(domain: "Reclaimer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No resource URL"])
        }
        return try load(from: url)
    }

    static func load(from url: URL) throws -> Catalog {
        let data = try Data(contentsOf: url)
        var cat = try JSONDecoder().decode(Catalog.self, from: data)
        cat.rawJSON = String(decoding: data, as: UTF8.self)
        return cat
    }

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }
}

/// Locates bundled files (catalog.json, web/). Normally these live in
/// Reclaimer.app/Contents/Resources. Debug builds run as a bare binary from
/// Xcode or `swift run`, with no bundle, so they fall back to the source tree.
enum Resources {
    static let root: URL? = {
        if let res = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: res.appendingPathComponent("catalog.json").path) {
            return res
        }
        #if DEBUG
        // Sources/Reclaimer/Catalog.swift → repo root
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: repo.appendingPathComponent("Package.swift").path) {
            return repo
        }
        #endif
        return nil
    }()

    static func url(_ relativePath: String) -> URL? { root?.appendingPathComponent(relativePath) }
}

extension String {
    /// "~/x" → "/Users/me/x". Only a leading tilde is expanded.
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
}
