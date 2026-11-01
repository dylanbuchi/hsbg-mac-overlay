import XCTest
@testable import HSBGMacOverlay

final class TripleTurnsTests: XCTestCase {
    private let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"

    private func turn(_ number: Int) -> String {
        // The game's TURN tag counts both halves of a round: game turn N is tag 2N-1.
        "\(playback)     TAG_CHANGE Entity=GameEntity tag=TURN value=\(2 * number - 1) "
    }

    private func triples(_ value: Int) -> String {
        "\(playback)     TAG_CHANGE Entity=[entityName=Kay id=181 zone=PLAY zonePos=0 cardId=HERO player=16] tag=PLAYER_TRIPLES value=\(value) "
    }

    private func parser() -> PowerLogParser {
        let parser = PowerLogParser()
        parser.feed([
            "D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            "\(playback)     FULL_ENTITY - Updating [entityName=Kay id=181 zone=PLAY zonePos=0 cardId=HERO player=16] CardID=HERO",
            "\(playback)         tag=CARDTYPE value=HERO",
            "\(playback)         tag=PLAYER_ID value=2",
            "\(playback)         tag=PLAYER_LEADERBOARD_PLACE value=3",
        ])
        return parser
    }

    func testEachTripleRecordsTheTurnItWasSeen() {
        let parser = parser()
        parser.feed([turn(7), triples(1), turn(12), triples(2)])
        let player = parser.snapshot().players.first
        XCTAssertEqual(player?.triples, 2)
        XCTAssertEqual(player?.tripleTurns, [7, 12])
    }

    func testAJumpSeenLateRecordsNoTurn() {
        let parser = parser()
        parser.feed([turn(9), triples(2), turn(10), triples(3)])
        let player = parser.snapshot().players.first
        XCTAssertEqual(player?.triples, 3)
        XCTAssertEqual(player?.tripleTurns, [10], "the first two were not seen happening")
    }

    func testTheSameCountTwiceIsNotANewTriple() {
        let parser = parser()
        parser.feed([turn(5), triples(1), triples(1), turn(6), triples(1)])
        XCTAssertEqual(parser.snapshot().players.first?.tripleTurns, [5])
    }

    /// A reconnect writes a new CREATE_GAME and replays every entity with its current tags. Those values were
    /// not seen happening, so their turns stay unknown instead of becoming the reconnect turn.
    func testAReconnectLeavesTierAndTripleTurnsUnknown() {
        let parser = PowerLogParser()
        parser.feed([
            "D 12:00:00.0000000 GameState.DebugPrintPower() - CREATE_GAME",
            "D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            turn(9),
            "\(playback)     FULL_ENTITY - Updating [entityName=Kay id=181 zone=PLAY zonePos=0 cardId=HERO player=16] CardID=HERO",
            "\(playback)         tag=CARDTYPE value=HERO",
            "\(playback)         tag=PLAYER_ID value=2",
            "\(playback)         tag=PLAYER_LEADERBOARD_PLACE value=3",
            "\(playback)         tag=PLAYER_TECH_LEVEL value=4",
            "\(playback)         tag=PLAYER_TRIPLES value=1",
        ])
        var player = parser.snapshot().players.first
        XCTAssertEqual(player?.tavernTier, 4)
        XCTAssertNil(player?.tierReachedTurn, "not 'Tier 4 on turn 9'")
        XCTAssertEqual(player?.triples, 1)
        XCTAssertEqual(player?.tripleTurns, [])

        // Later changes are seen happening again.
        parser.feed([turn(10),
                     "\(playback)     TAG_CHANGE Entity=[entityName=Kay id=181 zone=PLAY zonePos=0 cardId=HERO player=16] tag=PLAYER_TECH_LEVEL value=5 ",
                     triples(2)])
        player = parser.snapshot().players.first
        XCTAssertEqual(player?.tierReachedTurn, 10)
        XCTAssertEqual(player?.tripleTurns, [10])
        let card = NextOpponentContent(player: player!, lobby: [player!], currentTurn: 10)
        XCTAssertEqual(card.triples, "2 · turn 10")
    }

    func testAReplayedTierHasNoTurnOnTheCard() {
        var player = BattlegroundsPlayer(id: 2, name: "Kay")
        player.tavernTier = 4
        let card = NextOpponentContent(player: player, lobby: [player], currentTurn: 9)
        XCTAssertNil(card.tierTurn)
        XCTAssertEqual(card.tierPace, "T4")
    }

    func testCardTextShowsCountThenTheLastThreeTurns() {
        XCTAssertEqual(NextOpponentContent.triplesText(count: 1, turns: []), "1")
        XCTAssertEqual(NextOpponentContent.triplesText(count: 1, turns: [7]), "1 · turn 7")
        XCTAssertEqual(NextOpponentContent.triplesText(count: 2, turns: [7, 12]), "2 · turns 7, 12")
        XCTAssertEqual(NextOpponentContent.triplesText(count: 3, turns: [12]), "3 · turn 12", "only turns actually seen")
        XCTAssertEqual(NextOpponentContent.triplesText(count: 5, turns: [4, 6, 9, 11, 14]), "5 · turns …9, 11, 14")
    }

    func testCardContentUsesTheTurns() {
        var player = BattlegroundsPlayer(id: 2, name: "Kay")
        player.triples = 2
        player.tripleTurns = [7, 12]
        XCTAssertEqual(NextOpponentContent(player: player, lobby: [player], currentTurn: 13).triples, "2 · turns 7, 12")
    }
}
