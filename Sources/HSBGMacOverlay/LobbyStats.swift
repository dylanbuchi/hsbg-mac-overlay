import Foundation

/// Lobby average and your rank from ratings already fetched. Players the leaderboard
/// does not list (below roughly 8,000, renamed, or sharing a name) are counted, never guessed.
struct LobbyStats: Equatable {
    let playerCount: Int
    let listedCount: Int
    let average: Int?
    /// 1-based rank among the listed players; nil when you are not listed.
    let yourRank: Int?
    let youAreListed: Bool

    static func compute(players: [BattlegroundsPlayer]) -> LobbyStats? {
        let named = players.filter { !$0.name.isEmpty }
        let ratings = named.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        let average = Int((Double(ratings.reduce(0, +)) / Double(ratings.count)).rounded())
        let you = named.first(where: \.isLocalPlayer)
        let yourRating = you?.rating
        let rank = yourRating.map { mine in ratings.filter { $0 > mine }.count + 1 }
        return LobbyStats(playerCount: named.count, listedCount: ratings.count, average: average,
                          yourRank: rank, youAreListed: yourRating != nil)
    }

    var summary: String {
        var parts: [String] = []
        if let average { parts.append("Lobby avg \(Self.short(average))") }
        if let yourRank {
            parts.append("you #\(yourRank) of \(listedCount) listed")
        } else if playerCount > 0 {
            parts.append("you: unlisted")
        }
        let unlisted = playerCount - listedCount
        if unlisted > 0 { parts.append("\(unlisted) unlisted") }
        return parts.joined(separator: " · ")
    }

    /// 1-based rank among listed players and how many are listed; nil when `player` has no rating.
    static func rank(of player: BattlegroundsPlayer, in players: [BattlegroundsPlayer]) -> (rank: Int, listed: Int)? {
        guard let mine = player.rating else { return nil }
        let ratings = players.filter { !$0.name.isEmpty }.compactMap(\.rating)
        return (ratings.filter { $0 > mine }.count + 1, ratings.count)
    }

    /// Id of the player with the highest rating, when at least two are listed and one is strictly ahead.
    static func leaderID(in players: [BattlegroundsPlayer]) -> Int? {
        let listed = players.filter { !$0.name.isEmpty && $0.rating != nil }
        guard listed.count >= 2, let top = listed.max(by: { ($0.rating ?? 0) < ($1.rating ?? 0) }),
              listed.filter({ $0.rating == top.rating }).count == 1 else { return nil }
        return top.id
    }

    static func short(_ rating: Int) -> String {
        // Round half up in whole tenths, so 10,250 is always "10.3k".
        guard rating >= 1000 else { return "\(rating)" }
        let tenths = (rating + 50) / 100
        return "\(tenths / 10).\(tenths % 10)k"
    }
}
