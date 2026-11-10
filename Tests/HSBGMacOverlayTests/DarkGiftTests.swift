import XCTest
@testable import HSBGMacOverlay

final class DarkGiftTests: XCTestCase {
    private let playback = "D 02:16:12.5091440 PowerTaskList.DebugPrintPower() - "
    private let button = "[entityName=Dark Discovery id=433 zone=PLAY zonePos=0 cardId=BG36_Button_DarkGift player=7]"

    // Lines as Power.log writes them (2026-11-09).
    private func parserWithButton() -> PowerLogParser {
        let parser = PowerLogParser()
        parser.feed([
            "D 02:15:13.2634120 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            playback + "    FULL_ENTITY - Updating \(button) CardID=BG36_Button_DarkGift",
            playback + "        tag=CONTROLLER value=7",
            playback + "        tag=CARDTYPE value=GAME_MODE_BUTTON",
            playback + "        tag=TAG_SCRIPT_DATA_NUM_1 value=6",
            playback + "        tag=TAG_SCRIPT_DATA_NUM_2 value=3",
        ])
        return parser
    }

    private func usesLeft(_ value: Int) -> String {
        playback + "    TAG_CHANGE Entity=\(button) tag=TAG_SCRIPT_DATA_NUM_2 value=\(value) "
    }

    func testNoButtonMeansNoCount() {
        let parser = PowerLogParser()
        parser.feed("D 02:15:13.2634120 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS")
        XCTAssertNil(parser.darkGiftUsesLeft)
    }

    func testCountsDownFromThreeAsDiscoveriesAreUsed() {
        let parser = parserWithButton()
        XCTAssertEqual(parser.darkGiftUsesLeft, 3)
        parser.feed(usesLeft(2))
        XCTAssertEqual(parser.darkGiftUsesLeft, 2)
        parser.feed(usesLeft(1))
        parser.feed(usesLeft(0))
        XCTAssertEqual(parser.darkGiftUsesLeft, 0)
    }

    func testIgnoresAButtonControlledBySomeoneElse() {
        let parser = parserWithButton()   // button CONTROLLER=7
        parser.feed(playback + "    Player EntityID=20 PlayerID=5 GameAccountId=[hi=144 lo=1]")
        XCTAssertNil(parser.darkGiftUsesLeft, "you are player 5, the button is player 7's")
    }

    func testCountsYourOwnButtonOnceYouAreKnown() {
        let parser = parserWithButton()
        parser.feed(playback + "    Player EntityID=20 PlayerID=7 GameAccountId=[hi=144 lo=1]")
        XCTAssertEqual(parser.darkGiftUsesLeft, 3)
    }

    func testASecondButtonThatIsNotYoursDoesNotHideYourCount() {
        let parser = parserWithButton()   // yours: id 433, CONTROLLER=7
        parser.feed(playback + "    Player EntityID=20 PlayerID=7 GameAccountId=[hi=144 lo=1]")
        let other = "[entityName=Dark Discovery id=900 zone=PLAY zonePos=0 cardId=BG36_Button_DarkGift player=3]"
        parser.feed([playback + "    FULL_ENTITY - Updating \(other) CardID=BG36_Button_DarkGift",
                     playback + "        tag=CONTROLLER value=3",
                     playback + "        tag=TAG_SCRIPT_DATA_NUM_2 value=1"])
        XCTAssertEqual(parser.darkGiftUsesLeft, 3)
        parser.feed(usesLeft(2))
        XCTAssertEqual(parser.darkGiftUsesLeft, 2)
    }

    func testANewGameForgetsTheButton() {
        let parser = parserWithButton()
        parser.feed("D 02:47:41.1970040 GameState.DebugPrintPower() - CREATE_GAME")
        XCTAssertNil(parser.darkGiftUsesLeft)
    }

    func testCounterHidesWhenSpentOrWhenLabelsHide() {
        XCTAssertEqual(DarkGiftCounterRules.visibleCount(usesLeft: 2, showsTags: true), 2)
        XCTAssertNil(DarkGiftCounterRules.visibleCount(usesLeft: 0, showsTags: true))
        XCTAssertNil(DarkGiftCounterRules.visibleCount(usesLeft: 2, showsTags: false))
        XCTAssertNil(DarkGiftCounterRules.visibleCount(usesLeft: nil, showsTags: true))
    }

    func testCounterSitsUnderTheButton() {
        // The window the button was measured on: ring center about (1320, 243), radius about 38.
        let canvas = CGSize(width: 1600, height: 861)
        let size = DarkGiftCounterRules.size(canvas: canvas)
        XCTAssertEqual(size, DarkGiftCounterRules.baseSize)
        let center = DarkGiftCounterRules.center(canvas: canvas, size: size)
        XCTAssertEqual(center.x, 1320, accuracy: 10)
        XCTAssertGreaterThan(center.y - size.height / 2, 243 + 38)
        XCTAssertLessThan(center.y - size.height / 2, 243 + 60)
    }

    func testCounterGrowsWithTheWindowAndStaysInside() {
        let big = CGSize(width: 2000, height: 1093)
        XCTAssertGreaterThan(DarkGiftCounterRules.size(canvas: big).width, DarkGiftCounterRules.baseSize.width)
        for canvas in [big, CGSize(width: 1024, height: 768), CGSize(width: 800, height: 600)] {
            let size = DarkGiftCounterRules.size(canvas: canvas)
            let center = DarkGiftCounterRules.center(canvas: canvas, size: size)
            XCTAssertLessThanOrEqual(center.x + size.width / 2, canvas.width)
            XCTAssertGreaterThanOrEqual(center.x - size.width / 2, 0)
        }
    }
}
