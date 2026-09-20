import Foundation

/// The log file a user can attach to a bug report: ~/Library/Logs/Backspacer/Backspacer.log.
/// Plain text, one line per event, rotated once past `maxBytes` (one previous copy kept).
/// Nothing is ever sent anywhere; sharing it is the user's own act.
final class Diagnostics: Sendable {
    enum Level: String { case info, warn, error }

    let file: URL
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "backspacer.diagnostics")

    static let standard = Diagnostics(
        file: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Backspacer/Backspacer.log"),
        maxBytes: 1_000_000)

    init(file: URL, maxBytes: Int) { self.file = file; self.maxBytes = maxBytes }

    func log(_ level: Level, _ message: String) {
        let oneLine = message.replacingOccurrences(of: "\r\n", with: "⏎").replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\r", with: "⏎")
        let line = "\(Self.stamp(Date())) [\(level.rawValue)] \(oneLine)\n"
        queue.sync { append(line) }
    }

    /// `yyyy-MM-dd HH:mm:ss` in local time, without a DateFormatter (not Sendable).
    private static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
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
