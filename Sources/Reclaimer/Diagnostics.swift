import Foundation

/// The log file a user can attach to a bug report: ~/Library/Logs/Reclaimer/Reclaimer.log.
/// Plain text, one line per event, rotated once past `maxBytes` (one previous copy kept).
/// Nothing is ever sent anywhere; sharing it is the user's own act.
final class Diagnostics: @unchecked Sendable {
    enum Level: String { case info, warn, error }

    let file: URL
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "reclaimer.diagnostics")
    private let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    static let standard = Diagnostics(
        file: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Reclaimer/Reclaimer.log"),
        maxBytes: 1_000_000)

    init(file: URL, maxBytes: Int) { self.file = file; self.maxBytes = maxBytes }

    func log(_ level: Level, _ message: String) {
        let oneLine = message.replacingOccurrences(of: "\r\n", with: "⏎").replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\r", with: "⏎")
        let line = "\(stamp.string(from: Date())) [\(level.rawValue)] \(oneLine)\n"
        queue.sync { append(line) }
    }

    private func append(_ line: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? fm.attributesOfItem(atPath: file.path)[.size] as? Int, size + line.utf8.count > maxBytes {
            let previous = file.deletingPathExtension().appendingPathExtension("previous.log")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: file, to: previous)
        }
        if let h = FileHandle(forWritingAtPath: file.path) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}
