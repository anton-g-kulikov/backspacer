import Foundation
import Testing
@testable import Reclaimer

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

    @Test("C7 — only a leading tilde is expanded")
    func tilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect("~/x".expandingTilde == home + "/x")
        #expect("a/~/x".expandingTilde == "a/~/x")
        #expect("/abs".expandingTilde == "/abs")
    }
}
