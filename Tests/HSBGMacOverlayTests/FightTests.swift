import XCTest
@testable import HSBGMacOverlay

/// Health, damage taken in the last combat and the fights between you and one opponent.
final class FightTests: XCTestCase {
    private let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"

    private func hero(_ id: Int, player: Int, place: Int) -> [String] {
        ["\(playback)     FULL_ENTITY - Updating [entityName=Hero\(id) id=\(id) zone=SETASIDE zonePos=0 cardId=BG_HERO_\(id) player=16] CardID=BG_HERO_\(id)",
         "\(playback)         tag=CARDTYPE value=HERO",
         "\(playback)         tag=PLAYER_ID value=\(player)",
         "\(playback)         tag=HEALTH value=40",
         "\(playback)         tag=ARMOR value=5",
         "\(playback)         tag=PLAYER_LEADERBOARD_PLACE value=\(place)"]
    }

    private func tag(_ id: Int, _ name: String, _ value: Int) -> String {
        "\(playback)     TAG_CHANGE Entity=[entityName=Hero\(id) id=\(id) zone=SETASIDE zonePos=0 cardId=BG_HERO_\(id) player=16] tag=\(name) value=\(value) "
    }

    /// The opponent (player 3) is the stand-in's board; `changes` happen before the fight ends.
    private func fight(_ parser: PowerLogParser, turn: Int, changes: [String], firstCopy: Int) {
        let game = "\(playback)     TAG_CHANGE Entity=GameEntity"
        var lines = ["\(game) tag=TURN value=\(turn) ", "\(game) tag=BOARD_VISUAL_STATE value=2 "]
        lines += ["\(playback)     FULL_ENTITY - Updating [entityName=Copy id=\(firstCopy) zone=PLAY zonePos=0 cardId=BG_HERO_9 player=16] CardID=BG_HERO_9",
                  "\(playback)         tag=CARDTYPE value=HERO", "\(playback)         tag=ZONE value=PLAY",
                  "\(playback)         tag=CONTROLLER value=16", "\(playback)         tag=PLAYER_ID value=3",
                  "\(playback)         tag=HEALTH value=7"]
        lines += ["\(playback)     FULL_ENTITY - Updating [entityName=M id=\(firstCopy + 1) zone=PLAY zonePos=1 cardId=C player=16] CardID=C",
                  "\(playback)         tag=CARDTYPE value=MINION", "\(playback)         tag=ZONE value=PLAY",
                  "\(playback)         tag=CONTROLLER value=16", "\(playback)         tag=CARDRACE value=PIRATE",
                  "\(playback)     TAG_CHANGE Entity=[entityName=M id=\(firstCopy + 1) zone=PLAY zonePos=1 cardId=C player=16] tag=ATTACKING value=1 "]
        lines += ["\(game) tag=BOARD_VISUAL_STATE value=1 "] + changes + ["\(game) tag=STEP value=MAIN_CLEANUP "]
        parser.feed(lines)
    }

    private func newParser() -> PowerLogParser {
        let parser = PowerLogParser()
        parser.feed(["D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
                     "\(playback)     Player EntityID=20 PlayerID=8 GameAccountId=[hi=144 lo=1]",
                     "\(playback)     Player EntityID=24 PlayerID=16 GameAccountId=[hi=0 lo=0]"]
            + hero(10, player: 8, place: 1) + hero(30, player: 3, place: 2))
        return parser
    }

    private func player(_ parser: PowerLogParser, _ id: Int) -> BattlegroundsPlayer? {
        parser.snapshot().players.first { $0.id == id }
    }

    func testHealthIsMaximumMinusDamageAndArmorStaysApart() {
        let parser = newParser()
        parser.feed([tag(30, "DAMAGE", 12)])
        let p = player(parser, 3)
        XCTAssertEqual(p?.health, 40, "combat copies (HEALTH 7) must not override the leaderboard hero")
        XCTAssertEqual(p?.currentHealth, 28)
        XCTAssertEqual(p?.armor, 5)
    }

    func testDamageTakenInTheLastCombatCountsArmorFirstThenHealth() {
        let parser = newParser()
        fight(parser, turn: 11, changes: [tag(30, "ARMOR", 0), tag(30, "DAMAGE", 3)], firstCopy: 500)
        XCTAssertEqual(player(parser, 3)?.lastCombatDamage, 8)   // 5 armor + 3 health
        XCTAssertEqual(player(parser, 8)?.lastCombatDamage, 0)
        fight(parser, turn: 13, changes: [], firstCopy: 600)      // tie: nobody hurt
        XCTAssertEqual(player(parser, 3)?.lastCombatDamage, 0)
    }

    /// As in a real game (2026-11-09): the final combat starts (BOARD_VISUAL_STATE=2), the loser
    /// dies, and STEP goes to FINAL_GAMEOVER with no MAIN_CLEANUP and no return to the shop board.
    func testTheFinalFightOfTheGameIsCounted() {
        let parser = newParser()
        let game = "\(playback)     TAG_CHANGE Entity=GameEntity"
        parser.feed(["\(game) tag=TURN value=31 ", "\(game) tag=BOARD_VISUAL_STATE value=2 ",
                     tag(10, "DAMAGE", 45),
                     "\(game) tag=STEP value=MAIN_END ", "\(game) tag=STEP value=FINAL_WRAPUP ",
                     "\(game) tag=STEP value=FINAL_GAMEOVER "])
        XCTAssertTrue(parser.isGameOver)
        XCTAssertEqual(player(parser, 8)?.losses, 1)
        XCTAssertEqual(player(parser, 8)?.lastCombatDamage, 45)
        XCTAssertEqual(player(parser, 3)?.wins, 1)
    }

    func testGameOverWithoutAnOpenFightCountsNothing() {
        let parser = newParser()
        parser.feed(["\(playback)     TAG_CHANGE Entity=GameEntity tag=STEP value=FINAL_GAMEOVER "])
        XCTAssertEqual(player(parser, 8)?.wins, 0)
        XCTAssertEqual(player(parser, 8)?.losses, 0)
    }

    func testNoDamageKnownBeforeTheFirstCombat() {
        XCTAssertNil(player(newParser(), 3)?.lastCombatDamage)
    }

    func testFightsWithYouRecordWinnerTurnAndLosersDamage() {
        let parser = newParser()
        fight(parser, turn: 9, changes: [tag(10, "DAMAGE", 9)], firstCopy: 500)                  // they beat you for 9
        fight(parser, turn: 17, changes: [tag(30, "ARMOR", 0), tag(30, "DAMAGE", 7)], firstCopy: 600) // you beat them for 12
        fight(parser, turn: 19, changes: [], firstCopy: 700)                                     // draw: not recorded
        XCTAssertEqual(player(parser, 3)?.fightsWithYou, [
            FightWithYou(youWon: false, turn: 5, damage: 9),
            FightWithYou(youWon: true, turn: 9, damage: 12),
        ])
        XCTAssertTrue(player(parser, 8)?.fightsWithYou.isEmpty ?? false)
    }

    func testFightsResetWithANewGame() {
        let parser = newParser()
        fight(parser, turn: 9, changes: [tag(10, "DAMAGE", 9)], firstCopy: 500)
        parser.feed(["D 12:01:00.0000000 GameState.DebugPrintPower() -     CREATE_GAME"])
        XCTAssertNil(player(parser, 3))
    }
}
