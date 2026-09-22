import Foundation
import Testing
@testable import Backspacer

@Suite struct ShellModeTests {
    @Test("M1 — plain mode is /bin/sh with the system PATH")
    func plain() {
        let r = Shell.run("echo $0; echo $PATH", timeout: 10, login: false)
        let lines = r.stdout.split(separator: "\n").map(String.init)
        #expect(lines.first == "/bin/sh" || lines.first == "sh", Comment(rawValue: r.stdout))
        #expect(lines.last == "/usr/bin:/bin:/usr/sbin:/sbin", Comment(rawValue: r.stdout))
    }

    @Test("M2 — login mode is the user's zsh")
    func login() {
        let r = Shell.run("echo $ZSH_VERSION; echo $PATH", timeout: 30, login: true)
        let lines = r.stdout.split(separator: "\n").map(String.init)
        #expect(!(lines.first ?? "").isEmpty, "ZSH_VERSION set")
        #expect((lines.last ?? "").contains("/usr/local/bin") || (lines.last ?? "").contains("/opt/homebrew/bin") || (lines.last ?? "").split(separator: ":").count > 4, Comment(rawValue: r.stdout))
    }

    @Test("M3 — measurement is plain, catalog commands are login")
    func routing() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("backspacer-mode-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for d in ["Library/Caches", "Projects/a/node_modules", "Library/Logs"] { try FileManager.default.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true) }
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "p",  "group": "t", "bucket": "safe", "label": "caches", "path": "~/Library/Caches" },
          { "id": "g",  "group": "t", "bucket": "regen", "label": "nm", "glob": { "root": "~/Projects", "name": "node_modules", "maxdepth": 3, "type": "d" } },
          { "id": "c",  "group": "t", "bucket": "safe", "label": "custom", "path": "~/Library/Logs", "deleteCmd": "brew cleanup", "infoCmd": "brew info", "sizeCmd": "brew size" },
          { "id": "it", "group": "t", "bucket": "decide", "label": "items", "itemsCmd": "xcrun list", "deleteItemCmd": "xcrun rm {key}" }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8)); cat.rawJSON = json
        let shell = FakeShell()
        shell.on("xcrun list", stdout: "k1\tOne\t10\n")
        let bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path, shell: shell, diagnostics: Fixture.quiet)
        _ = try bridge.handle(op: "size", args: ["id": "p"])
        _ = try bridge.handle(op: "size", args: ["id": "g"])
        _ = try bridge.handle(op: "delete", args: ["id": "p"])
        _ = try bridge.handle(op: "size", args: ["id": "c"])
        _ = try bridge.handle(op: "info", args: ["id": "c"])
        _ = try bridge.handle(op: "delete", args: ["id": "c"])
        _ = try bridge.handle(op: "size", args: ["id": "it"])
        _ = try bridge.handle(op: "delete", args: ["id": "it", "item": "k1"])
        // catalog commands carry the PATH fallback prefix (M8); compare what follows it
        let tail = { (c: String) in c.components(separatedBy: "; ").last ?? c }
        let plain = shell.modes.filter { !$0.login }.map(\.command), login = shell.modes.filter { $0.login }.map { tail($0.command) }
        #expect(plain.allSatisfy { $0.hasPrefix("du ") || $0.hasPrefix("find ") || $0.hasPrefix("rm -rf ") }, Comment(rawValue: plain.joined(separator: " | ")))
        #expect(plain.contains { $0.hasPrefix("du -skxc") } && plain.contains { $0.hasPrefix("find ") } && plain.contains { $0.contains("rm -rf") })   // a sweep's rm follows its du in one plain call
        // sizeCmd runs twice: once for `size`, once inside `delete` for the before-bytes
        #expect(login.sorted() == ["brew cleanup", "brew info", "brew size", "brew size", "xcrun list", "xcrun list", "xcrun rm 'k1'"], Comment(rawValue: login.joined(separator: " | ")))
    }

    @Test("M4 — the breakdown works without zsh globbing")
    func breakdown() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("backspacer-bd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for (d, mb) in [("Library/Caches/big", 2), ("Library/Caches/small", 1)] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
            try Data(repeating: 0, count: mb * 1024 * 1024).write(to: home.appendingPathComponent(d + "/f"))
        }
        let json = #"{ "version": 1, "buckets": {}, "entries": [ { "id": "p", "group": "t", "bucket": "safe", "label": "c", "path": "~/Library/Caches" } ] }"#
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8)); cat.rawJSON = json
        let bridge = Bridge(catalog: cat, home: home.path, tildeHome: home.path, diagnostics: Fixture.quiet)
        let text = (try bridge.handle(op: "info", args: ["id": "p"]) as? [String: Any])?["text"] as? String ?? ""
        let lines = text.split(separator: "\n")
        try #require(lines.count == 2, Comment(rawValue: text))
        #expect(lines[0].hasSuffix("big") && lines[1].hasSuffix("small"))
    }

    @Test("M6 — the AppleScript wrapper escapes the command")
    func adminScript() {
        let cmd = "rm -rf " + Shell.q("/Users/t/It's \"here\"/x") + " && echo \\done"
        let src = Shell.adminScript(for: cmd)
        #expect(src.hasPrefix("do shell script \""))
        #expect(src.hasSuffix("\" with administrator privileges"))
        // inside the AppleScript string every " and \ of the command is escaped
        let inner = String(src.dropFirst("do shell script \"".count).dropLast("\" with administrator privileges".count))
        #expect(inner == cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))
    }

    @Test("M7 — admin work runs in a helper subprocess, not NSAppleScript on the app's main thread")
    func adminOffMainThread() {
        var spawned: [(String, [String])] = []
        let r = Shell.runAsAdmin("rm -rf '/x'", helper: "/Applications/Backspacer.app/Contents/MacOS/Backspacer",
                                 spawn: { exe, args, _ in spawned.append((exe, args)); return ShellResult(status: 0, stdout: "", stderr: "") })
        #expect(r.ok)
        #expect(spawned.count == 1)
        #expect(spawned.first?.0 == "/Applications/Backspacer.app/Contents/MacOS/Backspacer", "the app's own signed binary, so the prompt names Backspacer")
        #expect(spawned.first?.1 == [Shell.adminFlag, "rm -rf '/x'"])

        let cancelled = Shell.runAsAdmin("rm -rf '/x'", helper: "/x/Backspacer",
                                         spawn: { _, _, _ in ShellResult(status: 128, stdout: "", stderr: "cancelled\n") })
        #expect(!cancelled.ok && cancelled.stderr.contains("cancelled"))
    }

    @Test("M7b — the helper refuses anything but its flag")
    func helperGuards() {
        #expect(Shell.AdminHelper.main([]) == 64)
        #expect(Shell.AdminHelper.main(["--other", "x"]) == 64)
        #expect(Shell.AdminHelper.main([Shell.adminFlag]) == 64)
    }

    @Test("M8 — catalog commands get the known tool prefixes as a PATH fallback")
    func toolFallback() throws {
        let json = """
        { "version": 1, "buckets": {}, "entries": [
          { "id": "c", "group": "t", "bucket": "safe", "label": "custom", "infoCmd": "brew info" },
          { "id": "p", "group": "t", "bucket": "safe", "label": "plain", "path": "/Library/Developer/CoreSimulator/Caches", "sudo": true }
        ] }
        """
        var cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8)); cat.rawJSON = json
        let shell = FakeShell()
        let home = "/Users/tester"
        let bridge = Bridge(catalog: cat, home: home, tildeHome: home, pathPrefix: "/fake/bin", shell: shell, diagnostics: Fixture.quiet)
        _ = try bridge.handle(op: "info", args: ["id": "c"])
        _ = try bridge.handle(op: "size", args: ["id": "p"])
        let info = try #require(shell.calls.first { $0.contains("brew info") })
        #expect(info.hasPrefix("export PATH='/fake/bin':$PATH:"), Comment(rawValue: info))
        for prefix in ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/share/dotnet", home + "/.dotnet/tools", home + "/.cargo/bin", home + "/.bun/bin", home + "/.pub-cache/bin", home + "/.local/bin"] {
            #expect(info.contains(prefix), Comment(rawValue: prefix))
        }
        #expect(info.hasSuffix("; brew info"))
        let du = try #require(shell.calls.first { $0.hasPrefix("du ") })
        #expect(!du.contains("PATH"), "measurement runs in the plain shell with its fixed PATH")
    }

    @Test("M9 — a timeout kills the command's whole process group")
    func timeoutKillsGroup() {
        let start = Date()
        let r = Shell.run("sleep 31.7; echo x", timeout: 1, login: false)
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(!r.ok)
        #expect(!r.stdout.contains("x"))
        let check = Shell.run("pgrep -f '^sleep 31\\.7$' || true", timeout: 5, login: false)
        #expect(check.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Comment(rawValue: "orphans: \(check.stdout)"))
    }

    @Test("M10 — normal commands are unaffected by the group spawner")
    func normalCompletion() {
        let r = Shell.run("echo out; echo err 1>&2; exit 3", timeout: 5, login: false)
        #expect(r.status == 3 && r.stdout == "out\n" && r.stderr == "err\n")
        let big = Shell.run("head -c 200000 /dev/zero | tr '\\0' 'a'", timeout: 10, login: false)
        #expect(big.ok && big.stdout.utf8.count == 200_000)
    }

    @Test("M5 — ten plain dus are fast")
    func fast() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backspacer-fast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date()
        for _ in 0..<10 { _ = Shell.run("du -skxc \(Shell.q(dir.path)) 2>/dev/null", timeout: 10, login: false) }
        #expect(Date().timeIntervalSince(start) < 1.0)
    }
}
