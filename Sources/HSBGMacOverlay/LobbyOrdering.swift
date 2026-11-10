import Foundation

enum StableLobbyOrder {
    static func update(existing: [String], incoming: [String]) -> [String] {
        let incomingSet = Set(incoming)
        let retained = existing.filter { incomingSet.contains($0) }
        let retainedSet = Set(retained)
        let appended = incoming.filter { !retainedSet.contains($0) }
        return retained + appended
    }
}

enum LeaderboardMerge {
    struct Outcome: Equatable {
        var players: [BattlegroundsPlayer]
        /// Joins that did not work out, without player names (they go to the local diagnostics log).
        var issues: [String]
    }

    /// Joins HearthMirror lobby names to Power.log heroes and returns rows in the
    /// game's leaderboard order. Lobby order only breaks ties before places exist.
    static func players(
        mirrorPlayers: [(identity: String, player: HearthMirrorLobbySnapshot.Player)],
        parsed: [BattlegroundsPlayer],
        localPlayerName: String?,
        fallbackID: (String) -> Int
    ) -> [BattlegroundsPlayer] {
        merge(mirrorPlayers: mirrorPlayers, parsed: parsed, localPlayerName: localPlayerName,
              fallbackID: fallbackID).players
    }

    /// One-to-one: a log player gets at most one name, so two rows never share a player's stats (or a
    /// portrait). Exact hero ids are matched first, then base heroes (skins), then names (the log only
    /// names the local player). A name that matches no log player gets a row of its own with no place,
    /// which is not drawn; a log player that no name matched keeps its row without a name (tier only).
    /// A card id as it may appear in overlay.log: letters, digits and underscores only, at most 40,
    /// so whatever a reader returns, no name or other text can reach the file.
    static func logSafeID(_ id: String?) -> String {
        let kept = String((id ?? "").unicodeScalars.filter {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_"
        }.prefix(40).map(Character.init))
        return kept.isEmpty ? "?" : kept
    }

    static func merge(
        mirrorPlayers: [(identity: String, player: HearthMirrorLobbySnapshot.Player)],
        parsed: [BattlegroundsPlayer],
        localPlayerName: String?,
        fallbackID: (String) -> Int
    ) -> Outcome {
        var claim = [Int?](repeating: nil, count: mirrorPlayers.count)
        var taken = Set<Int>()
        func pass(_ matches: (HearthMirrorLobbySnapshot.Player, BattlegroundsPlayer) -> Bool) {
            for (index, entry) in mirrorPlayers.enumerated() where claim[index] == nil {
                if let found = parsed.indices.first(where: { !taken.contains($0) && matches(entry.player, parsed[$0]) }) {
                    claim[index] = found
                    taken.insert(found)
                }
            }
        }
        pass { mirror, log in !mirror.heroCardID.isEmpty && mirror.heroCardID == log.heroCardID }
        pass { mirror, log in
            !mirror.heroCardID.isEmpty && log.heroCardID.map(baseHeroID) == baseHeroID(mirror.heroCardID)
        }
        pass { mirror, log in !log.name.isEmpty && mirror.name == log.name }

        var usedIDs = Set(parsed.map(\.id))
        var merged: [BattlegroundsPlayer] = mirrorPlayers.enumerated().map { index, entry in
            var player: BattlegroundsPlayer
            if let found = claim[index] {
                player = parsed[found]
            } else {
                var id = fallbackID(entry.identity)
                while usedIDs.contains(id) { id += 1 }
                usedIDs.insert(id)
                player = BattlegroundsPlayer(id: id)
            }
            player.name = entry.player.name
            player.isLocalPlayer = localPlayerName.map { $0 == entry.player.name } ?? player.isLocalPlayer
            return player
        }
        let unclaimed = parsed.indices.filter { !taken.contains($0) }.map { parsed[$0] }
        merged += unclaimed

        var issues: [String] = []
        // Before the leaderboard exists (hero pick, lobby loading) nothing can match yet.
        if parsed.contains(where: { $0.placement != nil }) {
            for (index, entry) in mirrorPlayers.enumerated() where claim[index] == nil && !entry.player.heroCardID.isEmpty {
                let sameBase = mirrorPlayers.filter { baseHeroID($0.player.heroCardID) == baseHeroID(entry.player.heroCardID) }
                issues.append(sameBase.count > 1
                    ? "name for hero \(Self.logSafeID(entry.player.heroCardID)) lost: \(sameBase.count) names report that hero"
                    : "name for hero \(Self.logSafeID(entry.player.heroCardID)) matched no log player")
            }
            for player in unclaimed where player.placement != nil {
                issues.append("log place \(player.placement ?? 0) hero \(Self.logSafeID(player.heroCardID)) has no name")
            }
        }

        let players = merged.enumerated()
            .sorted { ($0.element.placement ?? Int.max, $0.offset) < ($1.element.placement ?? Int.max, $1.offset) }
            .map(\.element)
        return Outcome(players: players, issues: issues)
    }

    /// Skinned heroes log as e.g. `TB_BaconShop_HERO_16_SKIN_K`; compare the base hero.
    static func baseHeroID(_ cardID: String) -> String {
        guard let range = cardID.range(of: "_SKIN_") else { return cardID }
        return String(cardID[..<range.lowerBound])
    }
}

enum LobbyIdentity {
    static func identity(for player: HearthMirrorLobbySnapshot.Player) -> String {
        if !player.accountID.isEmpty && player.accountID != ":" {
            return "account:\(player.accountID)"
        }
        if !player.heroCardID.isEmpty {
            return "hero:\(player.heroCardID)"
        }
        return "name:\(player.name)"
    }

    /// A different lobby shows up as little overlap with the order kept so far.
    static func shouldResetOrder(existing: [String], incoming: [String]) -> Bool {
        guard !existing.isEmpty else { return true }
        let overlap = Set(existing).intersection(incoming).count
        return overlap < max(1, min(3, incoming.count / 2))
    }

    /// Ids for players the log has not shown yet. Real player ids are 1-16, so these start far above.
    static func fallbackID(_ identity: String) -> Int {
        let hash = identity.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return 1_000_000 + Int(hash.magnitude % 1_000_000)
    }
}
