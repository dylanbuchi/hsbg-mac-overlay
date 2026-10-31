import XCTest
@testable import HSBGMacOverlay

final class StreakAndRankTests: XCTestCase {
    func testWinAndLossStreaksDeriveFromTheSignedStreak() {
        var player = BattlegroundsPlayer(id: 1)
        XCTAssertEqual([player.winStreak, player.lossStreak], [0, 0])
        player.streak = 4
        XCTAssertEqual([player.winStreak, player.lossStreak], [4, 0])
        player.streak = -3
        XCTAssertEqual([player.winStreak, player.lossStreak], [0, 3])
    }

    private func lobby(_ ratings: [Int?]) -> [BattlegroundsPlayer] {
        ratings.enumerated().map { BattlegroundsPlayer(id: $0.offset + 1, name: "P\($0.offset + 1)", rating: $0.element) }
    }

    func testRankAmongListedPlayers() {
        let players = lobby([9000, nil, 12000, 8500])
        XCTAssertEqual(LobbyStats.rank(of: players[2], in: players)?.rank, 1)
        XCTAssertEqual(LobbyStats.rank(of: players[3], in: players)?.rank, 3)
        XCTAssertEqual(LobbyStats.rank(of: players[3], in: players)?.listed, 3)
        XCTAssertNil(LobbyStats.rank(of: players[1], in: players))
    }

    func testLeaderNeedsTwoListedAndNoTie() {
        XCTAssertEqual(LobbyStats.leaderID(in: lobby([9000, nil, 12000, 8500])), 3)
        XCTAssertNil(LobbyStats.leaderID(in: lobby([9000, nil, nil])))
        XCTAssertNil(LobbyStats.leaderID(in: lobby([9000, 9000, 8000])))
    }
}
