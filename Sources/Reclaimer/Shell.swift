import Foundation

struct ShellResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
    var combined: String { (stdout + (stderr.isEmpty ? "" : "\n" + stderr)).trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum Shell {
    /// Runs a command through a login zsh so PATH matches the user's Terminal
    /// (xcrun, brew, dotnet, npm all resolve).
    static func run(_ command: String, timeout: TimeInterval = 600) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch {
            return ShellResult(status: -1, stdout: "", stderr: "launch failed: \(error.localizedDescription)")
        }
        // Read concurrently so a chatty command can't fill the pipe and deadlock.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
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
