import Foundation
@testable import Reclaimer

/// Scripted stand-in for the system shell. `answers` are matched by substring, first match wins;
/// anything unmatched succeeds with empty output. Every call is recorded.
final class FakeShell: CommandRunner, @unchecked Sendable {
    var answers: [(contains: String, result: ShellResult)] = []
    var calls: [String] = []
    var adminCalls: [String] = []

    func on(_ fragment: String, stdout: String = "", stderr: String = "", status: Int32 = 0) {
        answers.append((fragment, ShellResult(status: status, stdout: stdout, stderr: stderr)))
    }
    private func answer(_ cmd: String) -> ShellResult {
        answers.first { cmd.contains($0.contains) }?.result ?? ShellResult(status: 0, stdout: "", stderr: "")
    }
    func run(_ command: String, timeout: TimeInterval) -> ShellResult { calls.append(command); return answer(command) }
    func runAsAdmin(_ command: String) -> ShellResult { adminCalls.append(command); return answer(command) }
}
