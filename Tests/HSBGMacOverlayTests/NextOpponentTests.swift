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
        XCTAssertEqual(content.lastBoard, "—")
        XCTAssertEqual(content.triples, "—")
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

    func testFallbackPositionIsOnePercentLeftAndSixtyPercentDown() {
        let layout = NextOpponentLayout(canvas: CGSize(width: 1600, height: 1000), trackerPanel: nil)
        XCTAssertEqual(layout.origin.x, 16, accuracy: 0.001)
        XCTAssertEqual(layout.origin.y, 600, accuracy: 0.001)
        XCTAssertEqual(layout.width, 220, accuracy: 0.001)
    }

    func testFallbackScalesWithTheWindow() {
        let small = NextOpponentLayout(canvas: CGSize(width: 800, height: 500), trackerPanel: nil)
        XCTAssertEqual(small.origin.x, 8, accuracy: 0.001)
        XCTAssertEqual(small.origin.y, 300, accuracy: 0.001)
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
        XCTAssertEqual(rows(1000), .init(showsTierPace: true, showsTriples: true))
        // 0.22 * 700 = 154 wide: scale 0.57, below both thresholds.
        XCTAssertEqual(rows(700), .init(showsTierPace: false, showsTriples: false))
        // 0.22 * 800 = 176 wide: scale 0.65, tier pace stays, triples go.
        XCTAssertEqual(rows(800), .init(showsTierPace: true, showsTriples: false))
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
        XCTAssertEqual(layout.origin.y, 600, accuracy: 0.001)
        XCTAssertTrue(layout.fits)
    }
}
