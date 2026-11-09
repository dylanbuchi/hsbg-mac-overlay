import XCTest
@testable import HSBGMacOverlay

final class TrinketTests: XCTestCase {
    private let playback = "D 02:22:05.0805020 PowerTaskList.DebugPrintPower() - "

    private func parserWithHero() -> PowerLogParser {
        let parser = PowerLogParser()
        parser.feed([
            "D 02:15:13.2634120 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            playback + "FULL_ENTITY - Creating ID=195 CardID=BG24_HERO_100",
            playback + "    tag=CARDTYPE value=HERO",
            playback + "    tag=PLAYER_ID value=4",
            playback + "    tag=PLAYER_LEADERBOARD_PLACE value=5",
        ])
        return parser
    }

    // Lines as Power.log writes them (2026-11-09), entity name and ids kept.
    private func change(_ tag: String, _ value: Int, id: Int = 195) -> String {
        playback + "    TAG_CHANGE Entity=[entityName=Sire Denathrius id=\(id) zone=SETASIDE zonePos=0 cardId=BG24_HERO_100 player=15] tag=\(tag) value=\(value) "
    }

    func testReadsBothTrinketsFromTheLeaderboardHero() {
        let parser = parserWithHero()
        XCTAssertNil(parser.snapshot().players.first?.lesserTrinketID)
        parser.feed(change("BACON_FIRST_TRINKET_DATABASE_ID", 130835))
        parser.feed(change("BACON_SECOND_TRINKET_DATABASE_ID", 131303))
        let player = parser.snapshot().players.first
        XCTAssertEqual(player?.lesserTrinketID, 130835)
        XCTAssertEqual(player?.greaterTrinketID, 131303)
    }

    func testATransformedTrinketReplacesTheIdAndZeroIsIgnored() {
        let parser = parserWithHero()
        parser.feed(change("BACON_FIRST_TRINKET_DATABASE_ID", 112991))
        parser.feed(change("BACON_FIRST_TRINKET_DATABASE_ID", 120926))
        parser.feed(change("BACON_FIRST_TRINKET_DATABASE_ID", 0))
        XCTAssertEqual(parser.snapshot().players.first?.lesserTrinketID, 120926)
    }

    func testCardContentListsTrinketsInOrder() {
        var player = BattlegroundsPlayer(id: 4, name: "Opponent#1234")
        XCTAssertEqual(NextOpponentContent(player: player, lobby: [player], currentTurn: 5).trinketIDs, [])
        player.greaterTrinketID = 131303
        player.lesserTrinketID = 130835
        XCTAssertEqual(NextOpponentContent(player: player, lobby: [player], currentTurn: 10).trinketIDs, [130835, 131303])
    }
}
