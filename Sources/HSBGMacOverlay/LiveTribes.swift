import Foundation

/// What one read of the game's leaderboard tribe data gave back.
enum TribeReadResult: Equatable, Sendable {
    /// Hero entity id -> (race id -> count), as the game holds it.
    case counts([Int: [Int: Int]])
    /// A short reason, for the status line; the overlay keeps working from the log.
    case unavailable(String)
}

/// Turns the game's raw race ids and counts into what the overlay shows.
enum LiveTribes {
    /// TAG_RACE ids -> the names Power.log uses (`CARDRACE`), so live and log data share one vocabulary.
    static let raceNames: [Int: String] = [
        11: "UNDEAD", 14: "MURLOC", 15: "DEMON", 17: "MECHANICAL", 18: "ELEMENTAL", 20: "BEAST",
        23: "PIRATE", 24: "DRAGON", 43: "QUILBOAR", 92: "NAGA", 126: "ABERRATION",
    ]
    static let allRaceID = 26

    /// Minions count once per type, so a dual-type minion adds to both and the total can exceed the
    /// board size. Amalgams (race ALL) belong to every tribe, so they are added to each real tribe
    /// present and never lead on their own. Unknown ids and zero counts are dropped.
    static func tribes(from raw: [Int: Int]) -> [String: Int] {
        let amalgams = max(raw[allRaceID] ?? 0, 0)
        var result: [String: Int] = [:]
        for (race, count) in raw where count > 0 {
            guard let name = raceNames[race] else { continue }
            result[name] = count + amalgams
        }
        return result
    }

    /// Tribes by player entity id, for the players the log knows; the rest stay nil (fall back).
    static func apply(_ counts: [Int: [Int: Int]]?, to players: inout [BattlegroundsPlayer]) {
        for index in players.indices {
            players[index].liveTribes = players[index].heroEntityID
                .flatMap { counts?[$0] }
                .map(tribes(from:))
        }
    }

    /// Biggest first; ties go to the tribe name so the order never flickers.
    static func ranked(_ tribes: [String: Int], limit: Int) -> [TribeCount] {
        tribes.filter { $0.value > 0 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { TribeCount(tribe: $0.key, count: $0.value) }
    }
}

extension TribeSummary {
    /// What goes under a portrait: the leading live tribe when the game's data is there, else the tribes
    /// of the last seen board (faded when old). The two are never merged.
    static func portrait(for player: BattlegroundsPlayer, currentTurn: Int) -> (tribes: [TribeCount], isStale: Bool) {
        if let live = player.liveTribes {
            let leading = LiveTribes.ranked(live, limit: 1)
            if !leading.isEmpty { return (leading, false) }
        }
        return (main(from: player.lastSeenTribes), isStale(lastSeenTurn: player.lastSeenTurn, currentTurn: currentTurn))
    }
}

/// The tribe row of the NEXT OPPONENT card: top three tribes, labelled live or with the turn they were seen.
struct TribesRow: Equatable {
    var tribes: [TribeCount]
    var isLive: Bool
    var seenTurn: Int?
    var isStale: Bool

    /// Tribes with a single minion are left out, as on the portraits (`TribeBadges.countText`); live counts
    /// that are all singles show nothing rather than an older board.
    static func make(for player: BattlegroundsPlayer, currentTurn: Int) -> TribesRow? {
        func counted(_ tribes: [String: Int]) -> [String: Int] { tribes.filter { TribeBadges.countText($0.value) != nil } }
        if let live = player.liveTribes, !LiveTribes.ranked(live, limit: 1).isEmpty {
            let top = LiveTribes.ranked(counted(live), limit: 3)
            return top.isEmpty ? nil : TribesRow(tribes: top, isLive: true, seenTurn: nil, isStale: false)
        }
        let seen = LiveTribes.ranked(counted(player.lastSeenTribes), limit: 3)
        guard !seen.isEmpty else { return nil }
        return TribesRow(tribes: seen, isLive: false, seenTurn: player.lastSeenTurn,
                         isStale: TribeSummary.isStale(lastSeenTurn: player.lastSeenTurn, currentTurn: currentTurn))
    }
}

/// Decides when the app reads tribe counts from game memory: only for a live Battlegrounds Solo match,
/// at most every few seconds, and never when the user switched it off.
struct TribePollGate {
    static let interval: TimeInterval = 3
    private(set) var lastRead: Date?
    /// Failed reads in a row; live data is dropped after `maxFailures` so a glitch does not flicker.
    private(set) var failures = 0
    static let maxFailures = 3

    func shouldRead(enabled: Bool, isBattlegrounds: Bool, isGameOver: Bool, hasMirror: Bool, now: Date) -> Bool {
        guard enabled, isBattlegrounds, !isGameOver, hasMirror else { return false }
        return lastRead.map { now.timeIntervalSince($0) >= Self.interval } ?? true
    }

    mutating func started(at date: Date) { lastRead = date }

    /// Returns true when the live data should be dropped.
    mutating func finished(success: Bool) -> Bool {
        failures = success ? 0 : failures + 1
        return failures >= Self.maxFailures
    }

    mutating func reset() { lastRead = nil; failures = 0 }
}
