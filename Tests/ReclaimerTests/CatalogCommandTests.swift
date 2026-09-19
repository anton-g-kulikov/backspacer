import Foundation
import Testing
@testable import Reclaimer

/// Runs catalog commands for real through `Shell.run`, with a fake `brew` first on PATH.
@Suite struct CatalogCommandTests {
    let catalog = try! Fixture.catalog()
    let fm = FileManager.default

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

    func screenshotsKB(home: URL) throws -> String {
        let cmd = try #require(catalog.entry("user-screenshots")?.sizeCmd)
        let r = Shell.run("HOME=\(Shell.q(home.path)); export HOME; " + cmd, timeout: 30, login: true)
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("B4 — screenshots entry measures 0 when nothing matches")
    func screenshotsEmpty() throws {
        let home = fm.temporaryDirectory.appendingPathComponent("reclaimer-shots-\(UUID().uuidString)")
        try fm.createDirectory(at: home.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        #expect(try screenshotsKB(home: home) == "0")
    }

    @Test("B5 — screenshots entry sums Screenshots/ and Desktop recordings")
    func screenshotsSum() throws {
        let home = fm.temporaryDirectory.appendingPathComponent("reclaimer-shots-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        for (rel, mb) in [("Screenshots/s.png", 1), ("Desktop/a.mov", 2), ("Desktop/notes.txt", 5)] {
            let url = home.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0, count: mb * 1024 * 1024).write(to: url)
        }
        #expect(try screenshotsKB(home: home) == "3072")
    }

    @Test("B3 — the check runs only from Info, never during a scan")
    func noSizeCmd() throws {
        let e = try #require(catalog.entry("cache-brew-orphans"))
        #expect(e.sizeCmd == nil)
        #expect(e.infoCmd != nil)
    }
}
