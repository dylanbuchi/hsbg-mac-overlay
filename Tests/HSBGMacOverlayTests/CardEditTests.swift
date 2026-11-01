import XCTest
@testable import HSBGMacOverlay

final class CardEditTests: XCTestCase {
    private let canvas = CGSize(width: 1920, height: 1080)

    func testScreenDeltaFlipsTheVerticalAxis() {
        let delta = CardEditGeometry.canvasDelta(fromScreen: CGPoint(x: 100, y: 500), to: CGPoint(x: 130, y: 460))
        XCTAssertEqual(delta, CGSize(width: 30, height: 40))
    }

    func testMovingKeepsTheScaleAndStaysInsideTheWindow() {
        let frame = CGRect(x: 100, y: 100, width: 270, height: 300)
        let moved = CardEditGeometry.moved(frame, by: CGSize(width: 50, height: -20), canvas: canvas)
        XCTAssertEqual(moved.origin(in: canvas).x, 150, accuracy: 0.5)
        XCTAssertEqual(moved.origin(in: canvas).y, 80, accuracy: 0.5)
        XCTAssertEqual(moved.scale(in: canvas), 1, accuracy: 0.01)

        let pastTheEdge = CardEditGeometry.moved(frame, by: CGSize(width: 5000, height: -5000), canvas: canvas)
        XCTAssertEqual(pastTheEdge.origin(in: canvas).x, canvas.width - frame.width, accuracy: 0.5)
        XCTAssertEqual(pastTheEdge.origin(in: canvas).y, 0, accuracy: 0.5)
    }

    func testResizingFollowsTheCornerWithinTheScaleRange() {
        let frame = CGRect(x: 100, y: 100, width: 270, height: 300)
        let bigger = CardEditGeometry.resized(frame, by: CGSize(width: 135, height: 0), canvas: canvas)
        XCTAssertEqual(bigger.scale(in: canvas), 1.5, accuracy: 0.01)
        XCTAssertEqual(bigger.origin(in: canvas).x, 100, accuracy: 0.5)
        let huge = CardEditGeometry.resized(frame, by: CGSize(width: 2000, height: 0), canvas: canvas)
        XCTAssertEqual(huge.scale(in: canvas), CardPlacement.scaleRange.upperBound, accuracy: 0.01)
        let tiny = CardEditGeometry.resized(frame, by: CGSize(width: -260, height: 0), canvas: canvas)
        XCTAssertEqual(tiny.scale(in: canvas), CardPlacement.scaleRange.lowerBound, accuracy: 0.01)
    }

    func testEditPanelSitsOverTheCardWithTheHintAbove() {
        let window = CGRect(x: 0, y: 40, width: 1920, height: 1080)
        let panel = CardEditGeometry.panelFrame(card: CGRect(x: 100, y: 200, width: 270, height: 300), canvasCocoaFrame: window)
        XCTAssertEqual(panel.minX, 100)
        XCTAssertEqual(panel.minY, 40 + 1080 - 500)
        XCTAssertEqual(panel.height, 300 + CardEditGeometry.hintHeight)
    }

    @MainActor
    func testModelEditingStateSaveAndReset() {
        let suite = "hsbg-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverlayModel(preferences: OverlayPreferences(defaults: defaults))
        XCTAssertFalse(model.isEditingCard)
        XCTAssertTrue(model.cardPlacements.isEmpty)

        let spot = CardPlacement.make(origin: CGPoint(x: 200, y: 300), scale: 1.2, canvas: canvas)
        model.saveCardPlacement(spot, canvas: canvas, persist: false)
        XCTAssertEqual(model.cardPlacements.placement(for: canvas), spot)
        XCTAssertTrue(OverlayPreferences(defaults: defaults).cardPlacements.isEmpty, "a drag in progress is not written")

        model.saveCardPlacement(spot, canvas: canvas)
        XCTAssertEqual(OverlayModel(preferences: OverlayPreferences(defaults: defaults)).cardPlacements.placement(for: canvas), spot)

        model.resetCardPlacement()
        XCTAssertTrue(model.cardPlacements.isEmpty)
        XCTAssertNil(defaults.data(forKey: CardPlacements.defaultsKey))
    }
}
