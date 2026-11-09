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

    func testCounterSitsJustRightOfTheButton() {
        // The window the button was measured on: ring center about (1320, 243), radius about 38.
        let canvas = CGSize(width: 1600, height: 861)
        let size = DarkGiftCounter.size
        let center = DarkGiftCounterRules.center(canvas: canvas, size: size)
        XCTAssertEqual(center.y, 243, accuracy: 3)
        XCTAssertGreaterThan(center.x - size.width / 2, 1320 + 38)
        XCTAssertLessThan(center.x - size.width / 2, 1320 + 60)
    }

    func testCounterDropsBelowTheButtonOnANarrowWindow() {
        let canvas = CGSize(width: 1024, height: 768)
        let size = DarkGiftCounter.size
        let center = DarkGiftCounterRules.center(canvas: canvas, size: size)
        XCTAssertLessThanOrEqual(center.x + size.width / 2, canvas.width)
        XCTAssertGreaterThan(center.y, 768 * 0.282)
    }
}
