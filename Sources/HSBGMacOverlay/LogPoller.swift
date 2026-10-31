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
    /// Bytes of Power.log not read yet; above zero the app is still catching up.
    var bytesRemaining: UInt64 = 0
    var fileSize: UInt64 = 0
}

/// Owns the log file state, the parser and the HearthMirror bridge, and runs them on
/// a private serial queue so a large catch-up read never blocks the main thread.
final class LogPoller: @unchecked Sendable {
    private let queue = DispatchQueue(label: "hsbg.log-poller", qos: .utility)
    private let locate: @Sendable () -> URL?
    private let readMirror: @Sendable () -> (snapshot: HearthMirrorLobbySnapshot?, error: String)
    private var parser = PowerLogParser()
    private var currentLogURL: URL?
    private var fileOffset: UInt64 = 0
    private var lineBuffer = LineBuffer()
    /// Upper bound per poll, so memory stays flat and the status can update while catching up.
    private let maxChunk: Int

    init(
        locate: @escaping @Sendable () -> URL? = { HearthstoneLogLocator.newestPowerLog },
        readMirror: (@Sendable () -> (snapshot: HearthMirrorLobbySnapshot?, error: String))? = nil,
        maxChunk: Int = 8 * 1024 * 1024
    ) {
        self.locate = locate
        self.maxChunk = maxChunk
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
            resetReading()
        }

        var size: UInt64 = 0
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            size = try handle.seekToEnd()
            // A deleted or rotated log is shorter than what was already read: start over.
            if size < fileOffset { resetReading() }
            try handle.seek(toOffset: fileOffset)
            let data = try handle.read(upToCount: maxChunk) ?? Data()
            fileOffset += UInt64(data.count)
            for line in lineBuffer.append(data) {
                parser.feed(line)
            }
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
            gamesStarted: parser.gamesStarted,
            bytesRemaining: size > fileOffset ? size - fileOffset : 0,
            fileSize: size
        )
    }

    private func resetReading() {
        fileOffset = 0
        lineBuffer.reset()
        parser = PowerLogParser()
    }
}
