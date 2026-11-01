import XCTest
@testable import HSBGMacOverlay

final class EdgeInkTests: XCTestCase {
    private func player(rating: Int? = 9000, wins: Int = 6, losses: Int = 1, streak: Int = 0,
                        name: String = "Tahdah#1234") -> BattlegroundsPlayer {
        var player = BattlegroundsPlayer(id: 1, name: name, rating: rating)
        player.wins = wins
        player.losses = losses
        player.streak = streak
        return player
    }

    // MARK: scaling

    func testSizesAreFractionsOfTheArtWidth() {
        let m = EdgeInkMetrics(width: 200)
        XCTAssertEqual(m.nameSize, 25.2, accuracy: 0.001)
        XCTAssertEqual(m.lineSize, 19.6, accuracy: 0.001)
        XCTAssertEqual(m.veilHeight, 106, accuracy: 0.001)
        XCTAssertEqual(m.sideInset, 12, accuracy: 0.001)
        XCTAssertEqual(m.gap, 2.8, accuracy: 0.001)
        XCTAssertEqual(m.cornerRadius, 14, accuracy: 0.001)
    }

    func testTextNeverDropsBelowEightPoints() {
        let m = EdgeInkMetrics(width: 50)
        XCTAssertEqual(m.nameSize, 8)
        XCTAssertEqual(m.lineSize, 8)
    }

    // MARK: drop order

    func testFullLineFitsWhenThereIsRoom() {
        let m = EdgeInkMetrics(width: 122)
        XCTAssertEqual(m.detail(mmr: "12,691", record: "6–1", streakDigits: 1), .full)
    }

    func testRecordGoesFirstThenStreakThenEverything() {
        // 8 pt floor at 64 pt wide: "12,691" + record + streak does not fit, MMR + streak does.
        let small = EdgeInkMetrics(width: 64)
        XCTAssertEqual(small.detail(mmr: "12,691", record: "12–3", streakDigits: 1), .mmrAndStreak)
        // Narrower: only MMR.
        let tight = EdgeInkMetrics(width: 45)
        XCTAssertEqual(tight.detail(mmr: "12,691", record: "12–3", streakDigits: 1), .mmr)
        // Too small for a second line at all.
        XCTAssertEqual(EdgeInkMetrics(width: 39).detail(mmr: "9,000", record: nil, streakDigits: nil), .none)
    }

    func testUnlistedPlayersKeepTheirRecordWhereRoomAllows() {
        let m = EdgeInkMetrics(width: 64)
        XCTAssertEqual(m.detail(mmr: "—", record: "6–1", streakDigits: 1), .full)
    }

    // MARK: content and streak data

    func testContentShowsNameWithoutTagAndFormattedMMR() {
        let content = EdgeInkContent(player: player(rating: 12691), isLeader: true)
        XCTAssertEqual(content.name, "Tahdah")
        XCTAssertEqual(content.mmr, "12,691")
        XCTAssertEqual(content.record, "6–1")
        XCTAssertTrue(content.isLeader)
    }

    func testUnlistedPlayerHasNoMMRText() {
        XCTAssertNil(EdgeInkContent(player: player(rating: nil), isLeader: false).mmr)
    }

    func testNoCombatsMeansNoRecord() {
        XCTAssertNil(EdgeInkContent(player: player(wins: 0, losses: 0), isLeader: false).record)
    }

    func testStreakDirectionAndThreshold() {
        XCTAssertNil(EdgeInkContent(player: player(streak: 1), isLeader: false).streak)
        XCTAssertNil(EdgeInkContent(player: player(streak: -1), isLeader: false).streak)
        XCTAssertNil(EdgeInkContent(player: player(streak: 0), isLeader: false).streak)
        XCTAssertEqual(EdgeInkContent(player: player(streak: 5), isLeader: false).streak, StreakRun(isLoss: false, count: 5))
        XCTAssertEqual(EdgeInkContent(player: player(streak: -3), isLeader: false).streak, StreakRun(isLoss: true, count: 3))
    }

    func testTriplesShowOnlyWhenThereIsAtLeastOne() {
        var p = player()
        XCTAssertNil(EdgeInkContent(player: p, isLeader: false).triples)
        p.triples = 0
        XCTAssertNil(EdgeInkContent(player: p, isLeader: false).triples)
        p.triples = 2
        XCTAssertEqual(EdgeInkContent(player: p, isLeader: false).triples, 2)
    }
}

final class TribeSummaryTests: XCTestCase {
    func testBiggestTribeFirstAndSecondOnlyFromThree() {
        XCTAssertEqual(TribeSummary.main(from: ["DRAGON": 5, "BEAST": 3, "MURLOC": 2]),
                       [TribeCount(tribe: "DRAGON", count: 5), TribeCount(tribe: "BEAST", count: 3)])
        XCTAssertEqual(TribeSummary.main(from: ["DRAGON": 5, "BEAST": 2]), [TribeCount(tribe: "DRAGON", count: 5)])
    }

    func testAtMostTwoTribesAndStableTies() {
        let result = TribeSummary.main(from: ["UNDEAD": 3, "BEAST": 3, "DEMON": 3])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.tribe), ["BEAST", "DEMON"])
    }

    func testEmptyAndZeroCountsShowNothing() {
        XCTAssertTrue(TribeSummary.main(from: [:]).isEmpty)
        XCTAssertTrue(TribeSummary.main(from: ["BEAST": 0]).isEmpty)
    }

    func testStaleAfterTwoTurns() {
        XCTAssertFalse(TribeSummary.isStale(lastSeenTurn: 5, currentTurn: 7))
        XCTAssertTrue(TribeSummary.isStale(lastSeenTurn: 5, currentTurn: 8))
        XCTAssertFalse(TribeSummary.isStale(lastSeenTurn: nil, currentTurn: 8))
    }

    func testEveryTribeHasItsOwnGlyphAndColour() {
        let styles = Array(TribeStyle.all.values)
        XCTAssertEqual(TribeStyle.all.count, 12)
        XCTAssertEqual(Set(styles.map(\.symbol)).count, styles.count)
        XCTAssertEqual(Set(styles.map { "\($0.red),\($0.green),\($0.blue)" }).count, styles.count)
        XCTAssertEqual(TribeStyle.style(for: "NOPE"), TribeStyle.unknown)
    }
}

final class CardTierTests: XCTestCase {
    func testCardContentCarriesTierAndTurn() {
        var p = BattlegroundsPlayer(id: 2, name: "A", placement: 1)
        XCTAssertNil(NextOpponentContent(player: p, lobby: [p], currentTurn: 3).tier)
        p.tavernTier = 5
        p.tierReachedTurn = 8
        let content = NextOpponentContent(player: p, lobby: [p], currentTurn: 9)
        XCTAssertEqual([content.tier, content.tierTurn], [5, 8])
        p.tavernTier = 1
        XCTAssertNil(NextOpponentContent(player: p, lobby: [p], currentTurn: 9).tierTurn)
    }
}

final class LeaderRuleTests: XCTestCase {
    private func p(_ id: Int, _ rating: Int?) -> BattlegroundsPlayer {
        var x = BattlegroundsPlayer(id: id, name: "P\(id)", placement: id)
        x.rating = rating
        return x
    }

    func testOnlyASingleTopRatingIsTheLeader() {
        XCTAssertEqual(LobbyStats.leaderID(in: [p(1, 9000), p(2, 12000), p(3, nil)]), 2)
        XCTAssertNil(LobbyStats.leaderID(in: [p(1, 12000), p(2, 12000)]))
        XCTAssertNil(LobbyStats.leaderID(in: [p(1, 12000), p(2, nil)]))
    }
}
