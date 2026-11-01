import XCTest
@testable import HSBGMacOverlay

final class NextOpponentTests: XCTestCase {
    private func lobby() -> [BattlegroundsPlayer] {
        var me = BattlegroundsPlayer(id: 1, name: "Me", placement: 3, rating: 8500)
        me.isLocalPlayer = true
        let a = BattlegroundsPlayer(id: 2, name: "Alpha#9", placement: 1, rating: 12000)
        let b = BattlegroundsPlayer(id: 3, name: "Beta", placement: 2)
        return [me, a, b]
    }

    private func pick(place: Int = 1, battlegrounds: Bool = true, combat: Bool = false, over: Bool = false,
                      players: [BattlegroundsPlayer]? = nil) -> BattlegroundsPlayer? {
        NextOpponentRules.opponent(players: players ?? lobby(), nextPlace: place, isBattlegrounds: battlegrounds,
                                   isInCombat: combat, isGameOver: over)
    }

    // MARK: visibility rules

    func testCardShowsInRecruitPhase() {
        XCTAssertEqual(pick()?.id, 2)
    }

    func testCardIsHiddenInCombat() {
        XCTAssertNil(pick(combat: true))
    }

    func testCardIsHiddenAfterTheGameEnds() {
        XCTAssertNil(pick(over: true))
    }

    func testCardIsHiddenWithoutANextOpponent() {
        XCTAssertNil(pick(place: 0))
        XCTAssertNil(pick(place: 7))
    }

    func testCardIsHiddenOutsideSoloBattlegrounds() {
        XCTAssertNil(pick(battlegrounds: false))
    }

    func testCardNeverShowsYouOrAnUnnamedPlayer() {
        XCTAssertNil(pick(place: 3))
        var players = lobby()
        players[1].name = ""
        XCTAssertNil(pick(players: players))
    }

    func testOnlyOneCardWhenTwoPlayersClaimAPlace() {
        var players = lobby()
        players[2].placement = 1
        XCTAssertNil(pick(players: players))
    }

    // MARK: content

    func testContentForAListedPlayer() {
        var alpha = lobby()[1]
        alpha.wins = 6
        alpha.losses = 1
        alpha.streak = 5
        alpha.tavernTier = 5
        alpha.tierReachedTurn = 8
        alpha.triples = 2
        alpha.lastSeenTribes = ["DRAGON": 5, "BEAST": 1]
        alpha.lastSeenTurn = 9
        alpha.lastBoardSize = 7
        alpha.lastBoardTier = 5
        let content = NextOpponentContent(player: alpha, lobby: lobby(), currentTurn: 10)
        XCTAssertEqual(content.name, "Alpha")
        XCTAssertEqual(content.mmr, "12,000")
        XCTAssertEqual(content.rank, "#1 of 2 listed")
        XCTAssertEqual(content.record, "6–1")
        XCTAssertEqual(content.streak, StreakRun(isLoss: false, count: 5))
        XCTAssertEqual(content.tierPace, "T5 on turn 8")
        XCTAssertEqual(content.lastBoard, "Dragons ×5 · 7 minions · T5")
        XCTAssertFalse(content.isLastBoardStale)
        XCTAssertEqual(content.triples, "2")
    }

    func testStaleBoardIsFlaggedAfterTwoTurns() {
        var alpha = lobby()[1]
        alpha.lastSeenTribes = ["UNDEAD": 3]
        alpha.lastSeenTurn = 4
        XCTAssertTrue(NextOpponentContent(player: alpha, lobby: lobby(), currentTurn: 7).isLastBoardStale)
        XCTAssertFalse(NextOpponentContent(player: alpha, lobby: lobby(), currentTurn: 6).isLastBoardStale)
    }

    func testUnknownThingsAreDashesNeverNumbers() {
        let beta = lobby()[2]   // unlisted, nothing fought, nothing known
        let content = NextOpponentContent(player: beta, lobby: lobby(), currentTurn: 3)
        XCTAssertEqual(content.mmr, "—")
        XCTAssertNil(content.rank)
        XCTAssertEqual(content.record, "—")
        XCTAssertNil(content.streak)
        XCTAssertEqual(content.tierPace, "—")
        XCTAssertEqual(content.lastBoard, "Not fought yet")
        XCTAssertFalse(content.hasLastBoard)
        XCTAssertNil(content.triples)
    }

    func testLossStreakAndTierWithoutATurn() {
        var beta = lobby()[2]
        beta.wins = 1
        beta.losses = 4
        beta.streak = -3
        beta.tavernTier = 3
        let content = NextOpponentContent(player: beta, lobby: lobby(), currentTurn: 5)
        XCTAssertEqual(content.streak, StreakRun(isLoss: true, count: 3))
        XCTAssertEqual(content.tierPace, "T3")
    }

    // MARK: layout, docking, clamping

    func testFallbackRestsOnTheBottomWithAnEightPercentMargin() {
        let layout = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000), trackerPanel: nil)
        XCTAssertEqual(layout.origin.x, 16, accuracy: 0.001)
        XCTAssertEqual(layout.origin.y + layout.height, 920, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.origin.y, 620)
        XCTAssertEqual(layout.width, 220, accuracy: 0.001)
    }

    func testFallbackScalesWithTheWindow() {
        let small = NextOpponentLayout(canvas: CGSize(width: 800, height: 500), trackerPanel: nil)
        XCTAssertEqual(small.origin.x, 8, accuracy: 0.001)
        XCTAssertEqual(small.origin.y + small.height, 460, accuracy: 0.001)
        XCTAssertEqual(small.width, 110, accuracy: 0.001)
    }

    func testDocksBelowHSTrackerWithAGapAndMatchesItsWidth() {
        let panel = CGRect(x: 20, y: 150, width: 240, height: 330)
        let layout = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000), trackerPanel: panel)
        XCTAssertEqual(layout.origin.x, 20, accuracy: 0.001)
        XCTAssertEqual(layout.origin.y, 480 + 12, accuracy: 0.001)
        XCTAssertEqual(layout.width, 240, accuracy: 0.001)
    }

    func testDockFollowsATallerPanel() {
        let short = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000),
                                       trackerPanel: CGRect(x: 20, y: 150, width: 240, height: 200))
        let tall = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000),
                                      trackerPanel: CGRect(x: 20, y: 150, width: 240, height: 300))
        XCTAssertEqual(tall.origin.y - short.origin.y, 100, accuracy: 0.001)
    }

    func testClampsInsideTheWindowAtTheBottom() {
        let panel = CGRect(x: 20, y: 400, width: 240, height: 520)
        let layout = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000), trackerPanel: panel)
        XCTAssertLessThanOrEqual(layout.origin.y + layout.height, 1000 - 10 + 0.001)
        XCTAssertGreaterThanOrEqual(layout.origin.y, 10)
    }

    func testClampsInsideTheWindowAtTheRightAndLeft() {
        let farRight = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000),
                                          trackerPanel: CGRect(x: 1500, y: 100, width: 240, height: 100))
        XCTAssertLessThanOrEqual(farRight.origin.x + farRight.width, 1600 - 16 + 0.001)
        let farLeft = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000),
                                         trackerPanel: CGRect(x: -50, y: 100, width: 240, height: 100))
        XCTAssertEqual(farLeft.origin.x, 16, accuracy: 0.001)
    }

    func testCardWidthIsCappedWhateverHSTrackerReports() {
        let huge = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000),
                                      trackerPanel: CGRect(x: 0, y: 0, width: 900, height: 100))
        XCTAssertEqual(huge.width, 320, accuracy: 0.001)
        let thin = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000),
                                      trackerPanel: CGRect(x: 0, y: 0, width: 20, height: 100))
        XCTAssertEqual(thin.width, 140, accuracy: 0.001)
    }

    func testRowsDropInOrderOnSmallWindows() {
        func rows(_ height: CGFloat) -> NextOpponentLayout.Rows {
            NextOpponentLayout(canvas: CGSize(width: height * 1.6, height: height), trackerPanel: nil).rows
        }
        XCTAssertEqual(rows(1000), .init(showsTierPace: true, showsStatus: true))
        // 0.22 * 700 = 154 wide: scale 0.57, below both thresholds.
        XCTAssertEqual(rows(700), .init(showsTierPace: false, showsStatus: false))
        // 0.22 * 800 = 176 wide: scale 0.65, tier pace stays, triples go.
        XCTAssertEqual(rows(800), .init(showsTierPace: true, showsStatus: false))
    }

    func testSmallerCardIsShorter() {
        let big = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000), trackerPanel: nil)
        let small = NextOpponentLayout(canvas: CGSize(width: 800, height: 500), trackerPanel: nil)
        XCTAssertLessThan(small.height, big.height)
        XCTAssertGreaterThan(small.scale, 0)
    }

    // MARK: HSTracker window picking and coordinates

    func testPicksTheLowestLeftPanelAndIgnoresBigAndRightWindows() {
        let canvas = CGSize(width: 1600, height: 1000)
        let frames = [
            CGRect(x: 0, y: 0, width: 1600, height: 1000),       // overlay covering the game
            CGRect(x: 20, y: 150, width: 240, height: 330),       // left panel
            CGRect(x: 1300, y: 100, width: 250, height: 700),     // right panel
            CGRect(x: 20, y: 90, width: 240, height: 40),         // small header
        ]
        XCTAssertEqual(TrackerPanelPicker.leftPanel(among: frames, canvas: canvas),
                       CGRect(x: 20, y: 150, width: 240, height: 330))
    }

    func testNoPanelWhenHSTrackerHasNoSuitableWindow() {
        let canvas = CGSize(width: 1600, height: 1000)
        XCTAssertNil(TrackerPanelPicker.leftPanel(among: [], canvas: canvas))
        XCTAssertNil(TrackerPanelPicker.leftPanel(among: [CGRect(x: 3000, y: 0, width: 240, height: 300)], canvas: canvas))
    }

    func testPanelIsClippedToTheGameWindow() {
        let canvas = CGSize(width: 1600, height: 1000)
        let panel = TrackerPanelPicker.leftPanel(among: [CGRect(x: -20, y: 600, width: 260, height: 600)], canvas: canvas)
        XCTAssertEqual(panel, CGRect(x: 0, y: 600, width: 240, height: 400))
    }

    func testGlobalToCanvasConversion() {
        // Primary screen 900 high; game content area at x 100, cocoa y 200..800 (CG top 100).
        let canvasFrame = CGRect(x: 100, y: 200, width: 1200, height: 600)
        let converted = CanvasCoordinates.canvasFrame(fromGlobal: CGRect(x: 120, y: 250, width: 240, height: 300),
                                                      canvasCocoaFrame: canvasFrame, primaryScreenMaxY: 900)
        XCTAssertEqual(converted, CGRect(x: 20, y: 150, width: 240, height: 300))
    }

    // MARK: never overlapping HSTracker's panel

    private let canvas = CGSize(width: 1600, height: 1000)

    private func assertBelowAndInside(_ layout: NextOpponentLayout, panel: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(layout.origin.y, panel.maxY + 12 - 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(layout.origin.y + layout.height, canvas.height, file: file, line: line)
    }

    func testCardFollowsAPanelThatGrowsFromFourToSixRows() {
        // Each "Latest Games" row adds about 25 pt to the panel.
        let four = CGRect(x: 0, y: 40, width: 240, height: 440)
        let six = CGRect(x: 0, y: 40, width: 240, height: 490)
        let before = NextOpponentLayout(canvas: canvas, trackerPanel: TrackerPanelPicker.leftPanel(among: [four], canvas: canvas))
        let after = NextOpponentLayout(canvas: canvas, trackerPanel: TrackerPanelPicker.leftPanel(among: [six], canvas: canvas))
        XCTAssertEqual(after.origin.y - before.origin.y, 50, accuracy: 0.001)
        assertBelowAndInside(after, panel: six)
    }

    func testTheLowestOfSeveralLeftWindowsDecides() {
        let frames = [CGRect(x: 0, y: 40, width: 240, height: 300), CGRect(x: 0, y: 340, width: 240, height: 260),
                      CGRect(x: 1300, y: 0, width: 250, height: 950)]
        let panel = TrackerPanelPicker.leftPanel(among: frames, canvas: canvas)
        XCTAssertEqual(panel?.maxY, 600)
        assertBelowAndInside(NextOpponentLayout(canvas: canvas, trackerPanel: panel), panel: panel!)
    }

    func testCardShrinksInsteadOfOverlappingWhenThePanelIsLow() {
        let panel = CGRect(x: 0, y: 40, width: 240, height: 760)   // bottom at 800
        let layout = NextOpponentLayout(canvas: canvas, trackerPanel: panel)
        XCTAssertTrue(layout.fits)
        XCTAssertLessThan(layout.scale, NextOpponentLayout(canvas: canvas, trackerPanel: nil).scale)
        assertBelowAndInside(layout, panel: panel)
    }

    func testCardIsHiddenWhenThereIsNoRoomAtAll() {
        let panel = CGRect(x: 0, y: 40, width: 240, height: 860)   // bottom at 900
        XCTAssertFalse(NextOpponentLayout(canvas: canvas, trackerPanel: panel).fits)
    }

    func testBigTransparentOverlayWindowIsNotAPanelSoTheFallbackApplies() {
        // As seen live: HSTracker has a window the size of the game, plus a narrow one in the middle.
        let frames = [CGRect(x: 0, y: 0, width: 1600, height: 1000), CGRect(x: 690, y: 0, width: 220, height: 1000)]
        XCTAssertNil(TrackerPanelPicker.leftPanel(among: frames, canvas: canvas))
        let layout = NextOpponentLayout(canvas: canvas, trackerPanel: nil)
        XCTAssertEqual(layout.origin.y + layout.height, 920, accuracy: 0.001)
        XCTAssertTrue(layout.fits)
    }
}

final class CardInCombatOptionTests: XCTestCase {
    private func pick(combat: Bool, option: Bool, over: Bool = false) -> BattlegroundsPlayer? {
        let players = DemoScenario.lobby(atGameStart: false).players
        return NextOpponentRules.opponent(players: players, nextPlace: DemoScenario.nextOpponentPlace,
                                          isBattlegrounds: true, isInCombat: combat, isGameOver: over,
                                          showsInCombat: option)
    }

    func testOptionOffHidesTheCardInCombat() {
        XCTAssertNil(pick(combat: true, option: false))
        XCTAssertNotNil(pick(combat: false, option: false))
    }

    func testOptionOnShowsTheSameCardInCombat() {
        XCTAssertEqual(pick(combat: true, option: true)?.name, "KoreanKombo")
        XCTAssertEqual(pick(combat: false, option: true)?.name, "KoreanKombo")
    }

    func testOptionNeverShowsTheCardAfterTheGame() {
        XCTAssertNil(pick(combat: true, option: true, over: true))
        XCTAssertNil(pick(combat: false, option: true, over: true))
    }

    func testPreferenceIsOffByDefaultAndPersists() {
        let suite = "hsbg-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OverlayPreferences(defaults: defaults)
        XCTAssertFalse(preferences.showsCardInCombat)
        preferences.showsCardInCombat = true
        XCTAssertTrue(OverlayPreferences(defaults: defaults).showsCardInCombat)
    }

    @MainActor
    func testModelReadsAndWritesThePreference() {
        let suite = "hsbg-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverlayModel(preferences: OverlayPreferences(defaults: defaults))
        XCTAssertFalse(model.showsCardInCombat)
        model.showsCardInCombat = true
        XCTAssertTrue(OverlayPreferences(defaults: defaults).showsCardInCombat)
        XCTAssertTrue(OverlayModel(preferences: OverlayPreferences(defaults: defaults)).showsCardInCombat)
    }

    func testDemoModeIsOnlyRequestedExplicitly() {
        XCTAssertFalse(DemoMode.isRequested(arguments: ["app"], environment: [:]))
        XCTAssertTrue(DemoMode.isRequested(arguments: ["app", "--demo"], environment: [:]))
        XCTAssertTrue(DemoMode.isRequested(arguments: ["app"], environment: ["HSBG_DEMO": "1"]))
    }

    func testDemoLobbyHasEightPlayersYouAndANextOpponent() {
        let players = DemoScenario.lobby(atGameStart: false).players
        XCTAssertEqual(players.count, 8)
        XCTAssertEqual(players.filter(\.isLocalPlayer).count, 1)
        XCTAssertEqual(Set(players.compactMap(\.placement)).count, 8)
    }
}

final class CardLeaderboardClearanceTests: XCTestCase {
    func testCardStaysLeftOfTheLeaderboardLabels() {
        for size in [CGSize(width: 1280, height: 780), CGSize(width: 1000, height: 780), CGSize(width: 1920, height: 1080)] {
            let layout = LeaderboardLayout(canvasSize: size, nextOpponentPlace: 2)
            let dock = NextOpponentLayout(canvas: size, trackerPanel: nil, rightLimit: layout.labelsLeftEdge)
            if dock.fits {
                XCTAssertLessThanOrEqual(dock.origin.x + dock.width, layout.labelsLeftEdge + 0.01, "\(size)")
            }
        }
    }

    func testNoLimitKeepsEarlierBehaviour() {
        let size = CGSize(width: 1920, height: 1080)
        let a = NextOpponentLayout(canvas: size, trackerPanel: nil)
        let b = NextOpponentLayout(canvas: size, trackerPanel: nil, rightLimit: nil)
        XCTAssertEqual(a.width, b.width)
    }
}

final class FallbackNeverCoversPanelTests: XCTestCase {
    func testTenRowPanelBottomStaysAboveTheFallbackCard() {
        // The tallest HSTracker panel in the demo ends at 0.035 + 0.58 of the height.
        for size in [CGSize(width: 1280, height: 780), CGSize(width: 1600, height: 1000), CGSize(width: 1920, height: 1080)] {
            let layout = NextOpponentLayout(canvas: size, trackerPanel: nil)
            XCTAssertTrue(layout.fits, "\(size)")
            XCTAssertGreaterThanOrEqual(layout.origin.y, size.height * (0.035 + 0.58), "\(size)")
        }
    }

    func testMeasuredPanelStillWinsOverTheFallback() {
        let canvas = CGSize(width: 1600, height: 1000)
        let panel = CGRect(x: 0, y: 35, width: 176, height: 470)
        let layout = NextOpponentLayout(canvas: canvas, trackerPanel: panel)
        XCTAssertGreaterThanOrEqual(layout.origin.y, panel.maxY)
    }
}


final class CardDataRowsTests: XCTestCase {
    private func opponent(_ edit: (inout BattlegroundsPlayer) -> Void = { _ in }) -> NextOpponentContent {
        var p = BattlegroundsPlayer(id: 3, name: "Alice#1", tavernTier: 4, health: 40, rating: 9045)
        edit(&p)
        let baseline = RatingBaseline(ratings: ["Alice": 9000], savedAt: Date(timeIntervalSince1970: 1_000))
        return NextOpponentContent(player: p, lobby: [p], currentTurn: 6, baseline: baseline,
                                   now: Date(timeIntervalSince1970: 1_000 + 6 * 3600))
    }

    func testZeroTriplesAreHiddenAndPositiveOnesShown() {
        XCTAssertNil(opponent { $0.triples = 0 }.triples)
        XCTAssertEqual(opponent { $0.triples = 2 }.triples, "2")
    }

    func testHealthIsMaximumMinusDamageWithArmorSeparate() {
        let c = opponent { $0.damageTaken = 17; $0.armor = 5; $0.lastCombatDamage = 9 }
        XCTAssertEqual(c.health, 23)
        XCTAssertEqual(c.armor, 5)
        XCTAssertEqual(c.lastCombatDamage, 9)
        XCTAssertTrue(c.hasStatusRow)
    }

    func testNothingToShowMeansNoStatusRow() {
        let c = opponent { $0.health = nil; $0.triples = nil; $0.armor = 0; $0.lastCombatDamage = 0 }
        XCTAssertNil(c.health)
        XCTAssertNil(c.lastCombatDamage)
        XCTAssertFalse(c.hasStatusRow)
    }

    func testRatingChangeComesFromTheBaseline() {
        XCTAssertEqual(opponent().mmrChange, RatingChange(delta: 45, window: "since 6 h"))
        XCTAssertNil(opponent { $0.rating = nil }.mmrChange)
    }

    func testVersusKeepsTheLatestFightOfEachKind() {
        let c = opponent {
            $0.fightsWithYou = [FightWithYou(youWon: false, turn: 3, damage: 4), FightWithYou(youWon: false, turn: 5, damage: 9),
                                FightWithYou(youWon: true, turn: 9, damage: 12)]
        }
        XCTAssertEqual(c.beatYou, FightWithYou(youWon: false, turn: 5, damage: 9))
        XCTAssertEqual(c.youBeatThem, FightWithYou(youWon: true, turn: 9, damage: 12))
        XCTAssertTrue(c.hasFightWithYou)
        XCTAssertEqual(NextOpponentCard.versusText(c.beatYou!, subject: "Beat you"), "Beat you · turn 5 (−9)")
        XCTAssertFalse(opponent().hasFightWithYou)
    }

    func testLayoutOmitsEmptyRowsAndAddsTheVersusRow() {
        let canvas = CGSize(width: 1600, height: 1000)
        let full = NextOpponentLayout(canvas: canvas, trackerPanel: nil)
        let noStatus = NextOpponentLayout(canvas: canvas, trackerPanel: nil, hasStatusRow: false)
        let versus = NextOpponentLayout(canvas: canvas, trackerPanel: nil, hasVersusRow: true)
        XCTAssertFalse(noStatus.rows.showsStatus)
        XCTAssertTrue(versus.rows.showsVersus)
        XCTAssertLessThan(noStatus.height, full.height)
        XCTAssertGreaterThan(versus.height, full.height)
        XCTAssertTrue(versus.fits)
        XCTAssertGreaterThanOrEqual(versus.origin.y, canvas.height * NextOpponentLayout.fallbackTop)
    }
}

final class DemoCardDataTests: XCTestCase {
    func testDemoOpponentShowsEveryNewLine() {
        let players = DemoScenario.lobby(atGameStart: false).players
        let opponent = players.first { $0.placement == DemoScenario.nextOpponentPlace }!
        let content = NextOpponentContent(player: opponent, lobby: players, currentTurn: 10, baseline: DemoScenario.baseline())
        XCTAssertEqual(content.mmrChange?.delta, -89)
        XCTAssertEqual(content.health, 23)
        XCTAssertEqual(content.armor, 4)
        XCTAssertEqual(content.lastCombatDamage, 9)
        XCTAssertTrue(content.hasFightWithYou)
        XCTAssertTrue(content.hasLastBoard)
        XCTAssertNotNil(content.triples)
    }

    func testGameStartShowsTheEmptyStates() {
        let players = DemoScenario.lobby(atGameStart: true).players
        let opponent = players.first { $0.placement == DemoScenario.nextOpponentPlace }!
        let content = NextOpponentContent(player: opponent, lobby: players, currentTurn: 1)
        XCTAssertEqual(content.lastBoard, "Not fought yet")
        XCTAssertNil(content.triples)
        XCTAssertNil(content.mmrChange)
        XCTAssertFalse(content.hasFightWithYou)
        XCTAssertEqual(content.health, 40)
    }
}
