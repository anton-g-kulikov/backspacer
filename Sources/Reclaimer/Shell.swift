import Foundation

struct ShellResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
    var combined: String { (stdout + (stderr.isEmpty ? "" : "\n" + stderr)).trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// What the bridge needs from a shell. `Shell` is the real one; tests inject a scripted stand-in.
protocol CommandRunner {
    /// `login: false` → `/bin/sh` with the system PATH (5 ms to start; enough for du/find/rm).
    /// `login: true`  → the user's login zsh (their PATH: brew, xcrun, dotnet…; ~0.8 s to start).
    func run(_ command: String, timeout: TimeInterval, login: Bool) -> ShellResult
    func runAsAdmin(_ command: String) -> ShellResult
}

/// The system shell, as a `CommandRunner`.
struct SystemShell: CommandRunner {
    func run(_ command: String, timeout: TimeInterval, login: Bool) -> ShellResult { Shell.run(command, timeout: timeout, login: login) }
    func runAsAdmin(_ command: String) -> ShellResult { Shell.runAsAdmin(command) }
}

enum Shell {
    /// Measurement and removal (`login: false`) run in `/bin/sh` with a fixed system PATH — the
    /// user's login profile costs ~0.8 s per command and isn't needed for du/find/rm. Catalog
    /// commands (`login: true`) go through a login zsh so PATH matches the user's Terminal
    /// (xcrun, brew, dotnet, npm all resolve).
    static func run(_ command: String, timeout: TimeInterval = 600, login: Bool = true) -> ShellResult {
        let p = Process()
        if login {
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", command]
        } else {
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", command]
            p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LANG": "en_US.UTF-8"]
        }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch {
            return ShellResult(status: -1, stdout: "", stderr: "launch failed: \(error.localizedDescription)")
        }
        // Drain both pipes concurrently so a chatty command can't fill one and deadlock. Real
        // threads, not GCD: many callers blocking in `group.wait` (three scan workers, or a
        // parallel test run) can starve the global queue and leave the readers never scheduled.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); Thread { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }.start()
        group.enter(); Thread { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }.start()
        let deadline = DispatchTime.now() + timeout
        if group.wait(timeout: deadline) == .timedOut { p.terminate() }
        p.waitUntilExit()
        return ShellResult(status: p.terminationStatus,
                           stdout: String(decoding: outData, as: UTF8.self),
                           stderr: String(decoding: errData, as: UTF8.self))
    }

    /// Runs a command as root via the system authorization dialog. Uses
    /// AppleScript's `do shell script … with administrator privileges`, which
    /// works under the hardened runtime and never sees the password.
    static func runAsAdmin(_ command: String) -> ShellResult {
        // NSAppleScript isn't thread-safe; hop to the main thread (the caller is on a background queue).
        if !Thread.isMainThread {
            var result = ShellResult(status: -1, stdout: "", stderr: "")
            DispatchQueue.main.sync { result = runAsAdmin(command) }
            return result
        }
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "authorization failed"
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
            // -128 = user cancelled the password dialog
            return ShellResult(status: Int32(code), stdout: "", stderr: code == -128 ? "cancelled" : msg)
        }
        return ShellResult(status: 0, stdout: result?.stringValue ?? "", stderr: "")
    }

    /// Single-quotes a path for safe interpolation into a shell command.
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
