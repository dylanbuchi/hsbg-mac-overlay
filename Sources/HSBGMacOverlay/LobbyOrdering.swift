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
    /// Joins HearthMirror lobby names to Power.log heroes and returns rows in the
    /// game's leaderboard order. Lobby order only breaks ties before places exist.
    static func players(
        mirrorPlayers: [(identity: String, player: HearthMirrorLobbySnapshot.Player)],
        parsed: [BattlegroundsPlayer],
        localPlayerName: String?,
        fallbackID: (String) -> Int
    ) -> [BattlegroundsPlayer] {
        var parsedByHero: [String: BattlegroundsPlayer] = [:]
        var parsedByName: [String: BattlegroundsPlayer] = [:]
        for player in parsed {
            if let heroCardID = player.heroCardID, !heroCardID.isEmpty {
                parsedByHero[baseHeroID(heroCardID)] = parsedByHero[baseHeroID(heroCardID)] ?? player
            }
            if !player.name.isEmpty {
                parsedByName[player.name] = player
            }
        }

        let merged: [BattlegroundsPlayer] = mirrorPlayers.map { identity, mirrorPlayer in
            let heroMatch = mirrorPlayer.heroCardID.isEmpty ? nil : parsedByHero[baseHeroID(mirrorPlayer.heroCardID)]
            var player = heroMatch
                ?? parsedByName[mirrorPlayer.name]
                ?? BattlegroundsPlayer(id: fallbackID(identity))
            player.name = mirrorPlayer.name
            player.isLocalPlayer = localPlayerName.map { $0 == mirrorPlayer.name } ?? player.isLocalPlayer
            return player
        }

        return merged.enumerated()
            .sorted { ($0.element.placement ?? Int.max, $0.offset) < ($1.element.placement ?? Int.max, $1.offset) }
            .map(\.element)
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
