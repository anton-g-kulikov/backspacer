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
    /// posix_spawn rather than Foundation.Process so the command starts in its own process group:
    /// on timeout the whole group is signalled, not just the shell, so no `du`/`rm` lives on as an
    /// orphan (R8). Foundation's Process can't set the group, and its children share the app's.
    static func spawn(_ executable: String, _ arguments: [String], timeout: TimeInterval, environment: [String: String]? = nil) -> ShellResult {
        var outFds: [Int32] = [-1, -1], errFds: [Int32] = [-1, -1]
        guard pipe(&outFds) == 0, pipe(&errFds) == 0 else { return ShellResult(status: -1, stdout: "", stderr: "launch failed: pipe") }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, outFds[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errFds[1], STDERR_FILENO)
        for fd in outFds + errFds { posix_spawn_file_actions_addclose(&actions, fd) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)

        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        // Reset the signal mask and dispositions: a child inherits the parent's, and a GUI app (or
        // the test runner) may have SIGTERM blocked — then the timeout's SIGTERM would never land.
        var noSignals = sigset_t(); sigemptyset(&noSignals)
        var allSignals = sigset_t(); sigfillset(&allSignals)
        posix_spawnattr_setsigmask(&attrs, &noSignals)
        posix_spawnattr_setsigdefault(&attrs, &allSignals)
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attrs, 0)   // 0: a new group whose id is the child's pid

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envPairs = (environment ?? ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }
        let envp = envPairs.map { strdup($0) } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attrs, argv, envp)
        close(outFds[1]); close(errFds[1])
        guard rc == 0 else {
            close(outFds[0]); close(errFds[0])
            return ShellResult(status: -1, stdout: "", stderr: "launch failed: \(String(cString: strerror(rc)))")
        }

        // Drain both pipes on dedicated threads (GCD's global queue can be starved by concurrent
        // callers blocked in group.wait) so a chatty command can't fill one and deadlock.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); Thread { outData = FileHandle(fileDescriptor: outFds[0], closeOnDealloc: true).readDataToEndOfFile(); group.leave() }.start()
        group.enter(); Thread { errData = FileHandle(fileDescriptor: errFds[0], closeOnDealloc: true).readDataToEndOfFile(); group.leave() }.start()

        var timedOut = false
        if group.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            killpg(pid, SIGTERM)
            if group.wait(timeout: .now() + 2) == .timedOut { killpg(pid, SIGKILL); group.wait() }
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let code: Int32 = timedOut ? -1 : (status & 0x7f) == 0 ? (status >> 8) & 0xff : -(status & 0x7f)
        return ShellResult(status: code,
                           stdout: String(decoding: outData, as: UTF8.self),
                           stderr: timedOut ? "timed out after \(Int(timeout)) s" : String(decoding: errData, as: UTF8.self))
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
    /// Backspacer's own executable is launched again as a subprocess in helper mode, and *that*
    /// process runs `do shell script … with administrator privileges` on its main thread. One
    /// prompt, attributed to Backspacer (same signed binary), while the app's main thread stays
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
