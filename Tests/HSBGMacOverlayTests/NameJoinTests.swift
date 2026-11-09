import XCTest
@testable import HSBGMacOverlay

final class NameJoinTests: XCTestCase {
    private func mirror(_ name: String, _ hero: String) -> (identity: String, player: HearthMirrorLobbySnapshot.Player) {
        ("name:\(name)", .init(name: name, heroCardID: hero, accountID: ""))
    }

    private func logPlayer(_ id: Int, hero: String?, place: Int?, tier: Int = 3) -> BattlegroundsPlayer {
        var player = BattlegroundsPlayer(id: id, heroCardID: hero, tavernTier: tier)
        player.placement = place
        return player
    }

    func testOneLogPlayerNeverGetsTwoNames() {
        // Two names report the same base hero (one stale): the exact id wins, the other gets no stats.
        let outcome = LeaderboardMerge.merge(
            mirrorPlayers: [mirror("Stale", "TB_BaconShop_HERO_16"), mirror("Right", "TB_BaconShop_HERO_16_SKIN_K")],
            parsed: [logPlayer(2, hero: "TB_BaconShop_HERO_16_SKIN_K", place: 1)],
            localPlayerName: nil, fallbackID: { _ in 2 })

        let right = outcome.players.first { $0.name == "Right" }
        let stale = outcome.players.first { $0.name == "Stale" }
        XCTAssertEqual(right?.id, 2)
        XCTAssertEqual(right?.placement, 1)
        XCTAssertNil(stale?.placement)
        XCTAssertNil(stale?.tavernTier)
        XCTAssertEqual(Set(outcome.players.map(\.id)).count, outcome.players.count, "row ids must be unique")
        XCTAssertEqual(outcome.issues, ["name for hero TB_BaconShop_HERO_16 lost: 2 names report that hero"])
    }

    func testExactHeroIsPreferredOverAnEarlierBaseMatch() {
        // Without the exact pass, the first name would take the first log player with that base hero.
        let outcome = LeaderboardMerge.merge(
            mirrorPlayers: [mirror("A", "BG20_HERO_283"), mirror("B", "BG20_HERO_283_SKIN_D4")],
            parsed: [logPlayer(4, hero: "BG20_HERO_283_SKIN_D4", place: 2), logPlayer(5, hero: "BG20_HERO_283", place: 5)],
            localPlayerName: nil, fallbackID: { _ in 900 })

        XCTAssertEqual(outcome.players.map(\.name), ["B", "A"])
        XCTAssertEqual(outcome.players.map(\.id), [4, 5])
        XCTAssertEqual(outcome.issues, [])
    }

    func testALogPlayerWithoutANameKeepsItsRowAndIsReported() {
        let outcome = LeaderboardMerge.merge(
            mirrorPlayers: [mirror("Known", "BG36_HERO_000"), mirror("Other", "BG99_HERO_999")],
            parsed: [logPlayer(3, hero: "BG36_HERO_000", place: 1), logPlayer(6, hero: "BG24_HERO_100", place: 2, tier: 4)],
            localPlayerName: nil, fallbackID: { _ in 700 })

        let unnamed = outcome.players.first { $0.id == 6 }
        XCTAssertEqual(unnamed?.name, "")
        XCTAssertEqual(unnamed?.tavernTier, 4)
        XCTAssertEqual(unnamed?.placement, 2)
        XCTAssertEqual(outcome.issues, ["name for hero BG99_HERO_999 matched no log player",
                                        "log place 2 hero BG24_HERO_100 has no name"])
    }

    func testNoIssuesBeforeTheLeaderboardExists() {
        let outcome = LeaderboardMerge.merge(
            mirrorPlayers: [mirror("Picking", "BG99_HERO_999")],
            parsed: [logPlayer(3, hero: nil, place: nil)],
            localPlayerName: nil, fallbackID: { _ in 700 })
        XCTAssertEqual(outcome.issues, [])
    }
}
