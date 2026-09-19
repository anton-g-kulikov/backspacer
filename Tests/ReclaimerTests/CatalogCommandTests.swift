import Foundation
import Testing
@testable import Reclaimer

/// Runs catalog commands for real through `Shell.run`, with a fake `brew` first on PATH.
@Suite struct CatalogCommandTests {
    let catalog = try! Fixture.catalog()

    /// Creates <dir>/bin/brew (prints `dryRun` for `autoremove -n`) and <dir>/Cellar/<formula>/1.0/blob of the given MB.
    func fakeBrew(dryRun: String, cellar: [String: Int]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reclaimer-brew-\(UUID().uuidString)")
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = "#!/bin/sh\nprintf '%s' " + Shell.q(dryRun) + "\n"
        let brew = bin.appendingPathComponent("brew")
        try script.write(to: brew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        for (name, mb) in cellar {
            let keg = dir.appendingPathComponent("Cellar/\(name)/1.0")
            try FileManager.default.createDirectory(at: keg, withIntermediateDirectories: true)
            try Data(repeating: 0, count: mb * 1024 * 1024).write(to: keg.appendingPathComponent("blob"))
        }
        return dir
    }

    func runInfo(with dir: URL) throws -> String {
        let e = try #require(catalog.entry("cache-brew-orphans"))
        let cmd = try #require(e.infoCmd)
        let r = Shell.run("export PATH=\(Shell.q(dir.appendingPathComponent("bin").path)):$PATH; " + cmd, timeout: 30)
        #expect(r.ok, Comment(rawValue: r.stderr))
        return r.combined
    }

    @Test("B1 — lists orphans and totals their Cellar size")
    func listsAndTotals() throws {
        let dir = try fakeBrew(dryRun: "==> Would autoremove 2 unneeded formulae:\nlibfoo\nuser/tap/libbar\n",
                               cellar: ["libfoo": 2, "libbar": 1])
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = try runInfo(with: dir)
        #expect(out.contains("libfoo"))
        #expect(out.contains("user/tap/libbar"))
        #expect(out.hasSuffix("Total: 3 MB"), Comment(rawValue: out))
    }

    @Test("B2 — says so when there is nothing to remove")
    func nothingToRemove() throws {
        let dir = try fakeBrew(dryRun: "", cellar: [:])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try runInfo(with: dir) == "No orphaned dependencies.")
    }

    @Test("B3 — the check runs only from Info, never during a scan")
    func noSizeCmd() throws {
        let e = try #require(catalog.entry("cache-brew-orphans"))
        #expect(e.sizeCmd == nil)
        #expect(e.infoCmd != nil)
    }
}
