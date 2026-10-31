import Foundation

/// Everything the model needs from one pass over Power.log and HearthMirror.
struct LogPoll: Sendable {
    enum Outcome: Sendable { case noLog, readFailed, ok }

    var outcome: Outcome = .noLog
    var lobby = BattlegroundsLobby()
    var mirror: HearthMirrorLobbySnapshot?
    var mirrorError = "not connected"
    var isDuos = false
    var isGameOver = false
    var isInCombat = false
    var nextOpponentPlace = 0
    var turn = 0
    var gamesStarted = 0
}

/// Owns the log file state, the parser and the HearthMirror bridge, and runs them on
/// a private serial queue so a large catch-up read never blocks the main thread.
final class LogPoller: @unchecked Sendable {
    private let queue = DispatchQueue(label: "hsbg.log-poller", qos: .userInitiated)
    private let locate: @Sendable () -> URL?
    private let readMirror: @Sendable () -> (snapshot: HearthMirrorLobbySnapshot?, error: String)
    private var parser = PowerLogParser()
    private var currentLogURL: URL?
    private var fileOffset: UInt64 = 0
    /// Bytes after the last newline; a read can end in the middle of a multi-byte character.
    private var pendingBytes = Data()

    init(
        locate: @escaping @Sendable () -> URL? = { HearthstoneLogLocator.newestPowerLog },
        readMirror: (@Sendable () -> (snapshot: HearthMirrorLobbySnapshot?, error: String))? = nil
    ) {
        self.locate = locate
        if let readMirror {
            self.readMirror = readMirror
        } else {
            // The real bridge is only built when no fake is given, and is used on the poll queue only.
            nonisolated(unsafe) let bridge = HearthMirrorBridge()
            self.readMirror = { (bridge.readLobby(), bridge.lastError) }
        }
    }

    func poll() async -> LogPoll {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.pollSync()) }
        }
    }

    private func pollSync() -> LogPoll {
        guard let url = locate() else { return LogPoll(outcome: .noLog) }

        if currentLogURL != url {
            currentLogURL = url
            fileOffset = 0
            pendingBytes = Data()
            parser = PowerLogParser()
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: fileOffset)
            let data = try handle.readToEnd() ?? Data()
            fileOffset = handle.offsetInFile
            consume(data)
        } catch {
            return LogPoll(outcome: .readFailed)
        }

        let mirror = readMirror()
        return LogPoll(
            outcome: .ok,
            lobby: parser.snapshot(),
            mirror: mirror.snapshot,
            mirrorError: mirror.error,
            isDuos: parser.isDuos,
            isGameOver: parser.isGameOver,
            isInCombat: parser.isInCombat,
            nextOpponentPlace: parser.nextOpponentPlace ?? 0,
            turn: parser.turn,
            gamesStarted: parser.gamesStarted
        )
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        pendingBytes.append(data)
        // Split on newline bytes and decode whole lines only, so names in any script survive.
        guard let lastNewline = pendingBytes.lastIndex(of: 0x0A) else { return }
        let complete = pendingBytes[pendingBytes.startIndex...lastNewline]
        pendingBytes = Data(pendingBytes[pendingBytes.index(after: lastNewline)...])
        for line in complete.split(separator: 0x0A) {
            parser.feed(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .newlines))
        }
    }
}
