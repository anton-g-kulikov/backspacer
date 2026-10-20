// Does letting the user pick a folder in an open panel give a NON-SANDBOXED app access to a
// path that Full Disk Access protects? If it does, Backspacer could ask for the few folders it
// actually needs (iPhone backups above all) instead of demanding the master key to the Mac.
//
// Run it from a process that does NOT already have Full Disk Access — the Claude bash box is
// one; Terminal.app is not, if it is ticked in the list, and would answer "readable" before the
// panel even opens, which proves nothing:
//
//     swift _meta/fda-panel-probe.swift                      # ~/Library/Messages
//     swift _meta/fda-panel-probe.swift ~/Library/Safari     # or any other protected folder
//
// The panel opens INSIDE the folder under test; press Open without choosing anything and that
// folder is what comes back. If you navigate elsewhere the probe says so and the result is about
// wherever you went instead.
//
// Reading it: "before" must be denied or the test is void (a second run answers a different
// question — whether the grant survived the first one). Then, after picking the folder:
// Answered on macOS 27, 2026-10-20, for ~/Library/Messages and ~/Library/Safari:
//   after (plain read)              readable — the process itself gets in
//   after (child process)           readable — and so does a child, which is what decides it for
//                                   Backspacer, since it measures with `du` in a shell
//   a second run's "before"         readable — the grant outlives the process that earned it
//   `ls` from an unrelated shell    denied   — it does not leak to other programs
// So the grant is per app identity and per folder, inherited by children and kept across runs.
// Re-run this if macOS changes: the whole per-folder-consent idea rests on these four lines.
import AppKit

let target = NSString(string: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "~/Library/Messages").expandingTildeInPath
let name = (target as NSString).lastPathComponent

func read(_ path: String) -> String {
    do { _ = try FileManager.default.contentsOfDirectory(atPath: path); return "readable" }
    catch { return "denied — \((error as NSError).localizedDescription)" }
}

print("target: \(target)")
print("before: \(read(target))")

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let panel = NSOpenPanel()
panel.canChooseDirectories = true
panel.canChooseFiles = false
panel.allowsMultipleSelection = false
panel.directoryURL = URL(fileURLWithPath: target)
panel.message = "Press Open with “\(name)” shown — don't go up a level. Read-only experiment."
app.activate(ignoringOtherApps: true)

guard panel.runModal() == .OK, let url = panel.url else {
    print("panel: cancelled — nothing to report. Run it again and press Open with “\(name)” selected.")
    exit(0)
}
print("panel: picked \(url.path)")
if url.path != target {
    print("note: that is not \(target) — every line below is about what you actually picked.")
}
print("after (plain read): \(read(url.path))")

let scoped = url.startAccessingSecurityScopedResource()
print("after (security-scoped start: \(scoped)): \(read(url.path))")

// The one that matters here: Backspacer measures through a child process (`du` in a shell), and
// TCC decides per process. A listing passes the same gate as a size walk and cannot take minutes
// — `du` over a large folder would, which is what made an earlier run look like it had hung.
let quoted = "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
let child = Process()
child.executableURL = URL(fileURLWithPath: "/bin/sh")
child.arguments = ["-c", "ls -A \(quoted) >/dev/null 2>&1 && echo readable || echo denied"]
let pipe = Pipe(); child.standardOutput = pipe; child.standardError = pipe
try? child.run()
let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
child.waitUntilExit()
print("after (child process, as `du` runs): \(out)")

if scoped { url.stopAccessingSecurityScopedResource() }
