import AppKit
import Darwin
import Foundation
import GameMemory

struct LobbySnapshot: Sendable {
    struct Player: Sendable {
        let name: String
        let heroCardID: String
        let accountID: String
        /// The game's PLAYER_ID, the same number Power.log uses; the strongest key for the join.
        var playerID: Int? = nil
    }

    let gameUUID: String?
    let players: [Player]
    let localPlayerName: String?
}

/// Source of the leaderboard tribe counts; the real one reads game memory, tests inject fakes.
protocol LeaderboardTribeReading {
    func readTribes() -> TribeReadResult
}

/// The overlay's own read-only game reader (Sources/GameMemory). It gets Hearthstone's task port,
/// which needs the debugger entitlement and the user's OK, and only copies memory out: no writes,
/// no injection, no calls into the game. It never loads HSTracker's HearthMirror.
final class GameReaderBridge: LeaderboardTribeReading {
    private var memory: TaskMemory?
    private var walker: MonoWalker?
    private var processID: pid_t?
    /// When the task port was refused, so a denied prompt is not shown again every second.
    private var deniedAt: Date?
    private(set) var lastError = "not connected"
    private let hearthstonePID: () -> pid_t?
    private let now: () -> Date

    static let deniedMessage = "macOS did not allow reading the game; allow the prompt, then reopen the overlay"
    static let rosettaMessage = "Hearthstone runs under Rosetta; untick \"Open using Rosetta\" to see player names"
    static let waitingMessage = "waiting for lobby names"

    init(
        hearthstonePID: @escaping () -> pid_t? = {
            NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName == "Hearthstone" || $0.bundleURL?.lastPathComponent == "Hearthstone.app"
            })?.processIdentifier
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.hearthstonePID = hearthstonePID
        self.now = now
    }

    func readLobby() -> LobbySnapshot? {
        guard let pid = hearthstonePID() else {
            disconnect()
            lastError = "Hearthstone not found"
            return nil
        }
        if processID != pid {
            disconnect()
            processID = pid
            deniedAt = nil
        }
        guard let walker = connect(pid) else { return nil }
        do {
            let names = try BattlegroundsNames.read(walker)
            guard !names.isEmpty else {
                lastError = Self.waitingMessage
                return nil
            }
            lastError = "live"
            let players = names.sorted { $0.key < $1.key }.map {
                LobbySnapshot.Player(name: $0.value, heroCardID: "", accountID: "", playerID: $0.key)
            }
            return LobbySnapshot(gameUUID: nil, players: players, localPlayerName: nil)
        } catch {
            // Outside a match GameState has no instance: that is waiting, not a failure. Anything else
            // drops the cached metadata so the next poll walks again from the root domain.
            let reason = (error as? WalkError)?.description ?? "read failed"
            if reason.hasSuffix("is null") || reason == "static data unavailable" {
                lastError = Self.waitingMessage
            } else {
                self.walker = nil
                lastError = "game reader: \(reason)"
            }
            return nil
        }
    }

    /// The leaderboard tiles' tribe counts. Uses the connection `readLobby` already opened (same queue),
    /// so it never attaches to the game on its own.
    func readTribes() -> TribeReadResult {
        guard let walker, let pid = processID, hearthstonePID() == pid else {
            return .unavailable("not connected to the game yet")
        }
        do {
            let counts = try BattlegroundsTribes.read(walker)
            return counts.isEmpty ? .unavailable("waiting for the leaderboard") : .counts(counts)
        } catch {
            let reason = (error as? WalkError)?.description ?? "read failed"
            return .unavailable(reason.hasSuffix("is null") ? "waiting for the leaderboard" : "game reader: \(reason)")
        }
    }

    /// The lobby's tribes (TAG_RACE ids) for the tavern list, through the connection `readLobby` opened.
    /// Nil when not connected or the read fails; the list then shows every tribe.
    func readLobbyRaces() -> [Int]? {
        guard let walker, let pid = processID, hearthstonePID() == pid else { return nil }
        return try? BattlegroundsAvailableRaces.read(walker)
    }

    private func connect(_ pid: pid_t) -> MonoWalker? {
        if let walker { return walker }
        if TaskMemory.isTranslated(pid: pid) {
            lastError = Self.rosettaMessage
            return nil
        }
        // A refused prompt is retried after a minute, not on every poll.
        if let deniedAt, now().timeIntervalSince(deniedAt) < 60 {
            lastError = Self.deniedMessage
            return nil
        }
        do {
            let memory = try self.memory ?? TaskMemory(pid: pid)
            self.memory = memory
            let walker = try MonoConnector.walker(for: memory)
            self.walker = walker
            return walker
        } catch is TaskMemory.OpenError {
            deniedAt = now()
            lastError = Self.deniedMessage
        } catch {
            lastError = "game reader: \((error as? WalkError)?.description ?? "not ready")"
        }
        return nil
    }

    private func disconnect() {
        walker = nil
        memory = nil
        processID = nil
    }
}
