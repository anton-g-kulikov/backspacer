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
        login
            ? spawn("/bin/zsh", ["-lc", command], timeout: timeout)
            : spawn("/bin/sh", ["-c", command], timeout: timeout,
                    environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LANG": "en_US.UTF-8"])
    }

    /// Launches an executable directly (no shell), drains both pipes, enforces the timeout.
    static func spawn(_ executable: String, _ arguments: [String], timeout: TimeInterval, environment: [String: String]? = nil) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let environment { p.environment = environment }
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

    /// `do shell script "<command>" with administrator privileges`, with the command escaped for
    /// an AppleScript string literal.
    static func adminScript(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// The flag that turns this executable into the admin helper (see `AdminHelper`).
    static let adminFlag = "--admin"

    /// Runs a command as root via the system authorization dialog without freezing the app (R5):
    /// Reclaimer's own executable is launched again as a subprocess in helper mode, and *that*
    /// process runs `do shell script … with administrator privileges` on its main thread. One
    /// prompt, attributed to Reclaimer (same signed binary), while the app's main thread stays
    /// free. The app never sees the password.
    static func runAsAdmin(_ command: String) -> ShellResult {
        runAsAdmin(command, helper: Bundle.main.executablePath ?? CommandLine.arguments[0], spawn: { spawn($0, $1, timeout: $2) })
    }

    static func runAsAdmin(_ command: String, helper: String,
                           spawn: (String, [String], TimeInterval) -> ShellResult) -> ShellResult {
        let r = spawn(helper, [adminFlag, command], 1800)
        // The helper maps a cancelled dialog to exit 128 and writes "cancelled".
        return r
    }

    /// What the executable does when launched with `--admin <command>`: runs the command with
    /// administrator privileges via NSAppleScript on this (helper) process's main thread and
    /// exits with the command's status — 128 with "cancelled" on stderr if the dialog was
    /// dismissed. Used only by `runAsAdmin`; never reached in normal app launches.
    enum AdminHelper {
        static func main(_ arguments: [String]) -> Int32 {
            guard arguments.count >= 2, arguments[0] == Shell.adminFlag else { return 64 }
            let command = arguments[1]
            var errorInfo: NSDictionary?
            let result = NSAppleScript(source: Shell.adminScript(for: command))?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 1
                let msg = code == -128 ? "cancelled" : ((errorInfo[NSAppleScript.errorMessage] as? String) ?? "authorization failed")
                FileHandle.standardError.write(Data((msg + "\n").utf8))
                return code == -128 ? 128 : 1
            }
            if let out = result?.stringValue, !out.isEmpty { FileHandle.standardOutput.write(Data((out + "\n").utf8)) }
            return 0
        }
    }

    /// Single-quotes a path for safe interpolation into a shell command.
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
