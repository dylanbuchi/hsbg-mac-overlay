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
        XCTAssertEqual(m.detail(mmr: "12,691", hasLeaderDiamond: false, record: "6–1", streakDigits: 1), .full)
    }

    func testRecordGoesFirstThenStreakThenEverything() {
        // 8 pt floor at 64 pt wide: "12,691" + record + streak does not fit, MMR + streak does.
        let small = EdgeInkMetrics(width: 64)
        XCTAssertEqual(small.detail(mmr: "12,691", hasLeaderDiamond: false, record: "12–3", streakDigits: 1), .mmrAndStreak)
        // Narrower: only MMR.
        let tight = EdgeInkMetrics(width: 45)
        XCTAssertEqual(tight.detail(mmr: "12,691", hasLeaderDiamond: false, record: "12–3", streakDigits: 1), .mmr)
        // Too small for a second line at all.
        XCTAssertEqual(EdgeInkMetrics(width: 39).detail(mmr: "9,000", hasLeaderDiamond: false, record: nil, streakDigits: nil), .none)
    }

    func testUnlistedPlayersKeepTheirRecordWhereRoomAllows() {
        let m = EdgeInkMetrics(width: 64)
        XCTAssertEqual(m.detail(mmr: "—", hasLeaderDiamond: false, record: "6–1", streakDigits: 1), .full)
    }

    func testLeaderDiamondTakesRoom() {
        // At 72 pt the line just fits without the diamond (62.4 of 63.4 pt) and not with it.
        let m = EdgeInkMetrics(width: 72)
        XCTAssertEqual(m.detail(mmr: "12,691", hasLeaderDiamond: false, record: "10–2", streakDigits: 1), .full)
        XCTAssertLessThan(m.detail(mmr: "12,691", hasLeaderDiamond: true, record: "10–2", streakDigits: 1), .full)
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
}
