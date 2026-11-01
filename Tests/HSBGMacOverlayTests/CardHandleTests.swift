import XCTest
@testable import HSBGMacOverlay

final class CardHandleTests: XCTestCase {
    private let card = CGRect(x: 100, y: 200, width: 270, height: 300)

    func testHandlesSitJustInsideTheCard() {
        let grip = CardHandleGeometry.grip(card: card)
        let corner = CardHandleGeometry.corner(card: card)
        XCTAssertTrue(card.contains(grip))
        XCTAssertTrue(card.contains(corner))
        XCTAssertEqual(grip.midX, card.midX)
        XCTAssertEqual(grip.minY, card.minY + CardHandleGeometry.inset)
        XCTAssertEqual(corner.maxX, card.maxX - CardHandleGeometry.inset)
        XCTAssertEqual(corner.maxY, card.maxY - CardHandleGeometry.inset)
        XCTAssertFalse(grip.intersects(corner))
    }

    func testHandlesShowOverTheCardAndJustAroundIt() {
        XCTAssertTrue(CardHandleGeometry.showsHandles(at: CGPoint(x: 200, y: 300), card: card))
        XCTAssertTrue(CardHandleGeometry.showsHandles(at: CGPoint(x: card.maxX + 5, y: card.maxY + 5), card: card))
        XCTAssertFalse(CardHandleGeometry.showsHandles(at: CGPoint(x: card.maxX + 30, y: 300), card: card))
        XCTAssertFalse(CardHandleGeometry.showsHandles(at: CGPoint(x: 10, y: 10), card: .zero), "no card, no handles")
    }

    func testHandleHitTestOnlyCoversTheHandles() {
        XCTAssertTrue(CardHandleGeometry.isOnHandle(CardHandleGeometry.grip(card: card).center, card: card))
        XCTAssertTrue(CardHandleGeometry.isOnHandle(CardHandleGeometry.corner(card: card).center, card: card))
        XCTAssertFalse(CardHandleGeometry.isOnHandle(CGPoint(x: card.midX, y: card.midY), card: card))
        XCTAssertFalse(CardHandleGeometry.isOnHandle(.zero, card: .zero))
    }

    func testHandleScreenFrameFlipsIntoCocoaCoordinates() {
        let window = CGRect(x: 50, y: 40, width: 1920, height: 1080)
        let frame = CardHandleGeometry.screenFrame(CGRect(x: 10, y: 20, width: 30, height: 40), canvasCocoaFrame: window)
        XCTAssertEqual(frame, CGRect(x: 60, y: 40 + 1080 - 60, width: 30, height: 40))
    }

    func testMinionTilesNeverSitUnderTheHandlesOnARealCard() {
        // Board tiles start at the card's left padding, so the corner handle (right edge) can only meet a tile
        // when the board is full; the zoom then gives way to the handle (see MinionZoomController.currentHit).
        let tiles = MinionZoomGeometry.tileFrames(board: CGRect(x: 14, y: 200, width: 242, height: 30), count: 7,
                                                  origin: card.origin, scale: 1)
        let grip = CardHandleGeometry.grip(card: card)
        XCTAssertFalse(tiles.contains { $0.intersects(grip) })
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
