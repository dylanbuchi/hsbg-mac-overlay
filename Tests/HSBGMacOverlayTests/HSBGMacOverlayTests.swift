import XCTest
@testable import HSBGMacOverlay

final class HSBGMacOverlayTests: XCTestCase {
    func testProjectSmokeTest() {
        XCTAssertTrue(true)
    }

    func testParsesBattlegroundsPlayerNamesAndTavernTiers() {
        let parser = PowerLogParser()
        parser.feed([
            "D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            "D 12:00:00.0000000 GameState.DebugPrintGame() - PlayerID=1, PlayerName=LocalPlayer",
            "D 12:00:00.0000000 GameState.DebugPrintGame() - PlayerID=2, PlayerName=Opponent",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() - Player EntityID=63 PlayerID=99 GameAccountId=[hi=0 lo=0]",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() - Player EntityID=64 PlayerID=1 GameAccountId=[hi=123 lo=456]",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() - FULL_ENTITY - Creating ID=64 CardID=TB_BaconShop_HERO_01",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     tag=PLAYER_ID value=1",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     tag=PLAYER_TECH_LEVEL value=4",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() - FULL_ENTITY - Creating ID=65 CardID=TB_BaconShop_HERO_02",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     tag=PLAYER_ID value=2",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     tag=PLAYER_TECH_LEVEL value=5",
        ])

        let lobby = parser.snapshot()
        XCTAssertTrue(lobby.isBattlegrounds)
        XCTAssertEqual(lobby.players.count, 2)
        XCTAssertEqual(lobby.players[0].name, "LocalPlayer")
        XCTAssertEqual(lobby.players[0].tavernTier, 4)
        XCTAssertTrue(lobby.players[0].isLocalPlayer)
        XCTAssertEqual(lobby.players[1].name, "Opponent")
        XCTAssertEqual(lobby.players[1].tavernTier, 5)
    }

    func testKeepsLobbyRowsStableWhenMirrorOrderChanges() {
        XCTAssertEqual(
            StableLobbyOrder.update(existing: ["a", "b", "c"], incoming: ["c", "a", "d"]),
            ["a", "c", "d"]
        )
    }

    func testRecordsLeaderboardHeroCardAndPlace() {
        let parser = PowerLogParser()
        parser.feed([
            "D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() - FULL_ENTITY - Creating ID=181 CardID=TB_BaconShop_HERO_16_SKIN_K",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     tag=CARDTYPE value=HERO",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     tag=PLAYER_ID value=2",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     tag=PLAYER_LEADERBOARD_PLACE value=1",
            "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() - TAG_CHANGE Entity=[entityName=A. F. Kay id=181 zone=SETASIDE zonePos=0 cardId=TB_BaconShop_HERO_16_SKIN_K player=16] tag=PLAYER_LEADERBOARD_PLACE value=3 ",
        ])

        let player = parser.snapshot().players.first
        XCTAssertEqual(player?.heroCardID, "TB_BaconShop_HERO_16_SKIN_K")
        XCTAssertEqual(player?.placement, 3)
    }

    func testTracksCombatAndGameOver() {
        let parser = PowerLogParser()
        let prefix = "D 12:00:00.0000000 GameState.DebugPrintPower() - TAG_CHANGE Entity=GameEntity"
        let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=GameEntity"
        parser.feed("\(playback) tag=BOARD_VISUAL_STATE value=2 ")
        XCTAssertTrue(parser.isInCombat)
        // Results arrive before the animation ends; only playback ends combat.
        parser.feed("\(prefix) tag=BOARD_VISUAL_STATE value=1 ")
        XCTAssertTrue(parser.isInCombat)
        parser.feed("\(playback) tag=BOARD_VISUAL_STATE value=1 ")
        XCTAssertFalse(parser.isInCombat)
        parser.feed("\(prefix) tag=STEP value=FINAL_GAMEOVER ")
        XCTAssertTrue(parser.isGameOver)
        parser.feed("D 12:00:00.0000000 GameState.DebugPrintPower() - CREATE_GAME")
        XCTAssertFalse(parser.isGameOver)
    }

    /// Combat results reach GameState before the animation shows them; places must
    /// only move when playback (PowerTaskList) gets there.
    func testLeaderboardPlacesFollowPlaybackNotGameState() {
        let parser = PowerLogParser()
        let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"
        parser.feed([
            "D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            // Playback writes entity creation as "Updating [...]" rather than "Creating ID=".
            "\(playback)     FULL_ENTITY - Updating [entityName=A. F. Kay id=181 zone=SETASIDE zonePos=0 cardId=TB_BaconShop_HERO_16_SKIN_K player=16] CardID=TB_BaconShop_HERO_16_SKIN_K",
            "\(playback)         tag=CARDTYPE value=HERO",
            "\(playback)         tag=PLAYER_ID value=2",
            "\(playback)         tag=PLAYER_LEADERBOARD_PLACE value=1",
            "\(playback)         tag=PLAYER_TECH_LEVEL value=3",
        ])
        let change = "TAG_CHANGE Entity=[entityName=A. F. Kay id=181 zone=SETASIDE zonePos=0 cardId=TB_BaconShop_HERO_16_SKIN_K player=16] tag=PLAYER_LEADERBOARD_PLACE value=4 "

        parser.feed("D 12:00:00.0000000 GameState.DebugPrintPower() - \(change)")
        XCTAssertEqual(parser.snapshot().players.first?.placement, 1)

        parser.feed("\(playback) \(change)")
        XCTAssertEqual(parser.snapshot().players.first?.placement, 4)

        // A replacement hero entity starts at tech level 0; keep the known tier.
        parser.feed([
            "\(playback)     FULL_ENTITY - Updating [entityName=A. F. Kay id=300 zone=PLAY zonePos=0 cardId=TB_BaconShop_HERO_16_SKIN_K player=16] CardID=TB_BaconShop_HERO_16_SKIN_K",
            "\(playback)         tag=PLAYER_ID value=2",
            "\(playback)         tag=PLAYER_TECH_LEVEL value=0",
        ])
        XCTAssertEqual(parser.snapshot().players.first?.tavernTier, 3)
    }

    /// A round runs from combat start to MAIN_CLEANUP; the loser's leaderboard hero
    /// takes damage (or loses armor) inside it. Shop-phase damage does not count.
    func testRecordsWinsLossesAndStreaks() {
        let parser = PowerLogParser()
        let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"
        func hero(_ id: Int, player: Int, place: Int) -> [String] {
            ["\(playback)     FULL_ENTITY - Updating [entityName=Hero\(id) id=\(id) zone=SETASIDE zonePos=0 cardId=BG_HERO_\(id) player=16] CardID=BG_HERO_\(id)",
             "\(playback)         tag=CARDTYPE value=HERO",
             "\(playback)         tag=PLAYER_ID value=\(player)",
             "\(playback)         tag=HEALTH value=30",
             "\(playback)         tag=ARMOR value=5",
             "\(playback)         tag=PLAYER_LEADERBOARD_PLACE value=\(place)"]
        }
        func tag(_ id: Int, _ name: String, _ value: Int) -> String {
            "\(playback)     TAG_CHANGE Entity=[entityName=Hero\(id) id=\(id) zone=SETASIDE zonePos=0 cardId=BG_HERO_\(id) player=16] tag=\(name) value=\(value) "
        }
        let game = "\(playback)     TAG_CHANGE Entity=GameEntity"
        func round(_ damage: [String]) -> [String] {
            ["\(game) tag=BOARD_VISUAL_STATE value=2 ", "\(game) tag=BOARD_VISUAL_STATE value=1 "]
                + damage + ["\(game) tag=STEP value=MAIN_CLEANUP "]
        }
        parser.feed(["D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS"]
            + hero(10, player: 1, place: 1) + hero(20, player: 2, place: 2))

        parser.feed(round([tag(20, "ARMOR", 2)]))               // player 2 loses through armor
        parser.feed([tag(10, "DAMAGE", 1)])                     // shop-phase self-damage: ignored
        parser.feed(round([tag(20, "DAMAGE", 4)]))              // player 2 loses again
        parser.feed(round([tag(10, "DAMAGE", 6)]))              // player 1 finally loses

        let players = Dictionary(uniqueKeysWithValues: parser.snapshot().players.map { ($0.id, $0) })
        XCTAssertEqual(players[1].map { [$0.wins, $0.losses, $0.streak] }, [2, 1, -1])
        XCTAssertEqual(players[2].map { [$0.wins, $0.losses, $0.streak] }, [1, 2, 1])
    }

    /// The opponent's combat board (controlled by the stand-in player) is counted by
    /// tribe at the first attack; amalgams add to every tribe on the board.
    func testSnapshotsOpponentTribesAtFirstAttack() {
        let parser = PowerLogParser()
        let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"
        func entity(_ id: Int, type: String, controller: Int, extra: [String] = []) -> [String] {
            ["\(playback)     FULL_ENTITY - Updating [entityName=E\(id) id=\(id) zone=PLAY zonePos=0 cardId=C\(id) player=\(controller)] CardID=C\(id)",
             "\(playback)         tag=CARDTYPE value=\(type)",
             "\(playback)         tag=ZONE value=PLAY",
             "\(playback)         tag=CONTROLLER value=\(controller)"] + extra.map { "\(playback)         \($0)" }
        }
        let game = "\(playback)     TAG_CHANGE Entity=GameEntity"
        parser.feed(["D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
                     "\(playback)     Player EntityID=24 PlayerID=16 GameAccountId=[hi=0 lo=0]",
                     "\(game) tag=TURN value=11 ",
                     "\(game) tag=BOARD_VISUAL_STATE value=2 "]
            + entity(500, type: "HERO", controller: 16, extra: ["tag=PLAYER_ID value=3"])
            + entity(501, type: "MINION", controller: 16, extra: ["tag=CARDRACE value=PIRATE"])
            + entity(502, type: "MINION", controller: 16, extra: ["tag=CARDRACE value=PIRATE"])
            + entity(503, type: "MINION", controller: 16, extra: ["tag=CARDRACE value=ALL"])
            + entity(504, type: "MINION", controller: 16, extra: ["tag=CARDRACE value=DEMON"])
            + entity(505, type: "MINION", controller: 8, extra: ["tag=CARDRACE value=DRAGON"])
            + ["\(playback)     TAG_CHANGE Entity=[entityName=E505 id=505 zone=PLAY zonePos=1 cardId=C505 player=8] tag=ATTACKING value=1 "])

        let opponent = parser.snapshot().players.first { $0.id == 3 }
        XCTAssertEqual(opponent?.lastSeenTribes, ["PIRATE": 3, "DEMON": 2])
        XCTAssertEqual(opponent?.lastSeenTurn, 6)
    }

    /// Duos pairs teammates on the leaderboard, which the Solo layout would mislabel.
    func testDuosIsNotTreatedAsSolo() {
        let parser = PowerLogParser()
        parser.feed("D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS_DUO")
        XCTAssertFalse(parser.isBattlegrounds)
        XCTAssertTrue(parser.isDuos)

        parser.feed("D 12:00:00.0000000 GameState.DebugPrintPower() - CREATE_GAME")
        parser.feed("D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS")
        XCTAssertTrue(parser.isBattlegrounds)
        XCTAssertFalse(parser.isDuos)
    }

    func testTracksNextOpponentPlaceFromLocalPlayerEntity() {
        let parser = PowerLogParser()
        let power = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"
        parser.feed([
            "D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            "\(power)     Player EntityID=23 PlayerID=8 GameAccountId=[hi=144115198130930000 lo=12345678]",
            "\(power)         tag=PLAYER_ID value=8",
            "\(power)         tag=NEXT_OPPONENT_PLAYER_ID value=3",
            "D 12:00:00.0000000 GameState.DebugPrintGame() - PlayerID=8, PlayerName=LocalPlayer#1234",
            "\(power) FULL_ENTITY - Creating ID=241 CardID=BG36_HERO_000",
            "\(power)     tag=CARDTYPE value=HERO",
            "\(power)     tag=PLAYER_ID value=3",
            "\(power)     tag=PLAYER_LEADERBOARD_PLACE value=2",
            "\(power) FULL_ENTITY - Creating ID=181 CardID=TB_BaconShop_HERO_16_SKIN_K",
            "\(power)     tag=CARDTYPE value=HERO",
            "\(power)     tag=PLAYER_ID value=2",
            "\(power)     tag=PLAYER_LEADERBOARD_PLACE value=5",
        ])
        XCTAssertEqual(parser.nextOpponentPlace, 2)

        // Later changes reference the player entity by name, sometimes by tag number.
        parser.feed("\(power) TAG_CHANGE Entity=LocalPlayer#1234 tag=1360 value=2 ")
        XCTAssertEqual(parser.nextOpponentPlace, 5)
    }

    /// Pins the layout to HSTracker's leaderboard formula on a 16:9 window: a 1440-wide
    /// 4:3 area inset by 240, LeftAdjust 0.0017 per slot, NextOpponentRightAdjust 0.023.
    func testLeaderboardLayoutMatchesHSTrackerFormula() {
        let size = CGSize(width: 1920, height: 1080)
        let plain = LeaderboardLayout(canvasSize: size, nextOpponentPlace: 0)
        let marked = LeaderboardLayout(canvasSize: size, nextOpponentPlace: 3)

        XCTAssertEqual(plain.top(for: 0), 162, accuracy: 0.001)
        XCTAssertEqual(plain.top(for: 3), 162 + 3 * 1080 * 0.69 / 8, accuracy: 0.001)
        XCTAssertEqual(plain.left(for: 0), 240 + 1440 * 4 * 0.0017, accuracy: 0.001)
        XCTAssertEqual(marked.left(for: 2), 240 + 1440 * (2 * 0.0017 + 0.023), accuracy: 0.001)
        XCTAssertEqual(LeaderboardLayout.scaledX(0.5, width: 0, height: 1080), 0)
    }

    func testMergeSortsMirrorNamesByLeaderboardPlace() {
        func mirror(_ name: String, _ hero: String) -> (identity: String, player: HearthMirrorLobbySnapshot.Player) {
            ("name:\(name)", .init(name: name, heroCardID: hero, accountID: ""))
        }
        var skinned = BattlegroundsPlayer(id: 2, heroCardID: "TB_BaconShop_HERO_16_SKIN_K", tavernTier: 4)
        skinned.placement = 1
        var plain = BattlegroundsPlayer(id: 3, heroCardID: "BG36_HERO_000", tavernTier: 3)
        plain.placement = 2
        var local = BattlegroundsPlayer(id: 8, name: "LocalPlayer", tavernTier: 5)
        local.placement = 3

        let players = LeaderboardMerge.players(
            mirrorPlayers: [
                mirror("LocalPlayer", "BG23_HERO_303"),
                mirror("Bob", "BG36_HERO_000"),
                mirror("Alice", "TB_BaconShop_HERO_16"),
                mirror("Late", ""),
            ],
            parsed: [local, plain, skinned],
            localPlayerName: "LocalPlayer",
            fallbackID: { _ in 999 }
        )

        XCTAssertEqual(players.map(\.name), ["Alice", "Bob", "LocalPlayer", "Late"])
        XCTAssertEqual(players.map(\.tavernTier), [4, 3, 5, nil])
        XCTAssertEqual(players.map(\.isLocalPlayer), [false, false, true, false])
    }

    func testParsesCachedLeaderboardResponse() {
        let ratings = LeaderboardClient.parseRatings("Alice 12000\n<br />Bob 9876\n")

        XCTAssertEqual(ratings["Alice"], 12000)
        XCTAssertEqual(ratings["Bob"], 9876)
    }

    /// Display names repeat on the leaderboard; a repeated name must not take someone else's rating.
    func testDropsLeaderboardNamesListedMoreThanOnce() {
        let ratings = LeaderboardClient.parseRatings("Sam 9000\nAlex 8500\nSam 7000\nSam 6000")

        XCTAssertEqual(ratings, ["Alex": 8500])
    }
}

