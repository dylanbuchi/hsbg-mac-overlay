import Foundation

/// A small local log for things the logs of the game cannot show afterwards (Power.log is emptied when the
/// game closes). Stays on this Mac, holds no player names or account ids, and keeps two files of
/// `maxBytes` at most: `overlay.log` and the previous one, `overlay.old.log`.
final class DiagnosticsLog: @unchecked Sendable {
    static let maxBytes = 256 * 1024
    static let shared = DiagnosticsLog(
        directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HSBGMacOverlay"))

    let directory: URL
    var now: @Sendable () -> Date = { Date() }
    private let queue = DispatchQueue(label: "hsbg.diagnostics", qos: .utility)
    private var lastIssues: [String] = []

    init(directory: URL) {
        self.directory = directory
    }

    var fileURL: URL { directory.appendingPathComponent("overlay.log") }

    /// Writes the name join issues when they change (the join runs every second), and once when they clear.
    func noteNameJoin(_ issues: [String]) {
        queue.sync {
            guard issues != lastIssues else { return }
            let lines = issues.isEmpty ? ["name join ok again"] : issues.map { "name join: \($0)" }
            lastIssues = issues
            append(lines)
        }
    }

    func note(_ line: String) {
        queue.sync { append([line]) }
    }

    private func append(_ lines: [String]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now())
        let data = Data(lines.map { "\(stamp) v\(AppInfo.version) \($0)\n" }.joined().utf8)
        let size = ((try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int) ?? 0
        if size + data.count > Self.maxBytes {
            let old = directory.appendingPathComponent("overlay.old.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: fileURL, to: old)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
