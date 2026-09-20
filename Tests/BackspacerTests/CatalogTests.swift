import Foundation
import Testing
@testable import Backspacer

@Suite struct CatalogTests {
    let catalog = try! Fixture.catalog()
    static let buckets: Set<String> = ["safe", "regen", "decide", "keep", "locked"]

    @Test("C1 — the shipped catalog decodes")
    func decodes() {
        #expect(catalog.version == 1)
        #expect(!catalog.entries.isEmpty)
        #expect(!catalog.rawJSON.isEmpty)
    }

    @Test("C2 — ids are unique")
    func uniqueIds() {
        let ids = catalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("C3 — every bucket is known")
    func knownBuckets() {
        for e in catalog.entries { #expect(Self.buckets.contains(e.bucket), Comment(rawValue: e.id)) }
    }

    @Test("C4 — isDeletable = deletable bucket, not manual, has a source")
    func deletableRule() {
        for e in catalog.entries {
            let expected = ["safe", "regen", "decide"].contains(e.bucket) && !(e.manual ?? false)
                && (e.path != nil || e.paths != nil || e.glob != nil || e.deleteCmd != nil)
            #expect(e.isDeletable == expected, Comment(rawValue: e.id))
        }
    }

    @Test("C5 — keep and locked are never deletable")
    func readOnlyBuckets() {
        for e in catalog.entries where e.bucket == "keep" || e.bucket == "locked" {
            #expect(!e.isDeletable, Comment(rawValue: e.id))
        }
    }

    @Test("C6 — lookup by id")
    func lookup() {
        let first = catalog.entries[0]
        #expect(catalog.entry(first.id)?.label == first.label)
        #expect(catalog.entry("no-such-entry") == nil)
    }

    @Test("C8 — Time Machine snapshots are accounting-only, managed by macOS")
    func snapshotsAreLocked() throws {
        let e = try #require(catalog.entry("regrow-snapshots"))
        #expect(e.bucket == "locked")
        #expect(!e.isDeletable)
        #expect(e.deleteCmd == nil)
        #expect(e.infoCmd != nil)
    }

    @Test("C9 — children: true entries have a single path and no custom delete")
    func childrenEntries() {
        let cs = catalog.entries.filter { $0.children == true }
        #expect(!cs.isEmpty)
        for e in cs {
            #expect(e.path != nil && e.paths == nil && e.glob == nil && e.deleteCmd == nil, Comment(rawValue: e.id))
        }
    }

    @Test("C10 — app-data revamp shape")
    func appDataShape() throws {
        let el = try #require(catalog.entry("electron-caches"))
        #expect(el.bucket == "safe")
        #expect(Set(el.glob?.names ?? []) == ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnWebGPUCache", "DawnGraphiteCache"])
        #expect(el.glob?.pathPatterns == ["*/Service Worker/CacheStorage"])
        #expect(el.glob?.maxdepth == 3)
        #expect(catalog.entry("app-slack") == nil)
        #expect(catalog.entry("vscode-cache")?.paths?.contains { $0.hasSuffix("/Code/Cache") } == false)
        #expect(catalog.entry("cache-user")?.children == true)
        #expect(catalog.entry("cache-dot")?.children == true)
        let bk = try #require(catalog.entry("ios-backups"))
        #expect(bk.children == true && bk.childLabel?.file == "Info.plist" && bk.childLabel?.keys == ["Device Name"])
        let ol = try #require(catalog.entry("ollama-models"))
        #expect(ol.itemsCmd != nil && ol.deleteItemCmd?.contains("{key}") == true)
    }

    @Test("C15 — catalog text is plain, never markup")
    func plainText() {
        for e in catalog.entries {
            #expect(!e.label.contains("<"), Comment(rawValue: e.id))
            #expect(!(e.note ?? "").contains("<"), Comment(rawValue: e.id))
        }
        let raw = catalog.rawJSON
        #expect(!raw.contains("\"blurb\": \"<"))
    }

    @Test("C14 — everything behind Full Disk Access says so")
    func fdaFlags() throws {
        let gated = ["~/Library/Containers", "~/Library/Group Containers", "~/Library/Messages", "~/Library/Mail", "~/Library/Safari", "MobileSync"]
        for e in catalog.entries {
            let paths = (e.path.map { [$0] } ?? []) + (e.paths ?? [])
            if paths.contains(where: { p in gated.contains { p.contains($0) } }) { #expect(e.fda == true, Comment(rawValue: e.id)) }
        }
        #expect(catalog.entry("app-mail-downloads")?.bucket == "safe")
        #expect(catalog.entry("app-teams-cache")?.bucket == "safe")
        #expect(catalog.entry("app-messages")?.manual == true, "the gate refuses ~/Library/Messages, so measure only")
    }

    @Test("C13 — AVDs are per-device with their .ini")
    func avdCompanion() throws {
        let e = try #require(catalog.entry("android-avd"))
        #expect(e.children == true && e.companion == ".ini")
        for x in catalog.entries where x.companion != nil { #expect(x.children == true, Comment(rawValue: x.id)) }
    }

    @Test("C12 — the logs sweep spares our diagnostics and crash reports")
    func logsExclude() throws {
        let e = try #require(catalog.entry("cache-logs"))
        #expect(e.children == true)
        #expect(Set(e.exclude ?? []) == ["Backspacer", "DiagnosticReports"])
        for x in catalog.entries where x.exclude != nil { #expect(x.children == true, Comment(rawValue: x.id)) }
    }

    @Test("C11 — admin never runs a catalog command")
    func noSudoCommands() {
        for e in catalog.entries where e.needsAdmin {
            #expect(e.deleteCmd == nil && e.deleteItemCmd == nil, Comment(rawValue: e.id))
        }
    }

    @Test("C7 — only a leading tilde is expanded")
    func tilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect("~/x".expandingTilde == home + "/x")
        #expect("a/~/x".expandingTilde == "a/~/x")
        #expect("/abs".expandingTilde == "/abs")
    }

    @Test("C16 — the Mac host keeps only entries that list macOS (or don't say); loadAll keeps every entry")
    func platformFilter() throws {
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "everywhere", "group": "t", "bucket": "safe", "label": "npm cache", "path": "~/.npm/_cacache", "platforms": ["macos", "linux", "windows"], "os": { "windows": { "path": "$LOCALAPPDATA/npm-cache" } } },
          { "id": "unsaid",     "group": "t", "bucket": "safe", "label": "Xcode DerivedData", "path": "~/Library/Developer/Xcode/DerivedData" },
          { "id": "linux-only", "group": "t", "bucket": "safe", "label": "apt cache", "path": "/var/cache/apt/archives", "platforms": ["linux"] },
          { "id": "win-only",   "group": "t", "bucket": "safe", "label": "%TEMP%", "path": "$TEMP", "platforms": ["windows"] }
        ] }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backspacer-platforms-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let mac = try Catalog.load(from: url)
        #expect(mac.entries.map(\.id) == ["everywhere", "unsaid"])
        #expect(mac.entries[0].platforms == ["macos", "linux", "windows"])
        #expect(mac.entries[0].os?["windows"]?.path == "$LOCALAPPDATA/npm-cache", "overrides decode, the Mac host just never reads them")
        // The page gets the filtered JSON: a foreign entry cannot reach it by accident.
        let page = try JSONSerialization.jsonObject(with: Data(mac.rawJSON.utf8)) as? [String: Any]
        let ids = (page?["entries"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        #expect(ids == ["everywhere", "unsaid"])
        #expect(page?["version"] as? Int == 1, "the rest of the document is preserved")
        #expect(!mac.rawJSON.contains("/var/cache/apt"))
        let all = try Catalog.loadAll(from: url)
        #expect(all.entries.map(\.id) == ["everywhere", "unsaid", "linux-only", "win-only"])
        let bridge = Bridge(catalog: mac, diagnostics: Fixture.quiet)
        let reply = try bridge.handle(op: "catalog", args: [:])
        #expect(!String(describing: reply).contains("linux-only"))
    }
}
