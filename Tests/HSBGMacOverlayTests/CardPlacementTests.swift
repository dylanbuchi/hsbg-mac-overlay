import CoreGraphics
import Foundation
import Testing
@testable import HSBGMacOverlay

@Suite struct CardPlacementTests {
    private func custom(_ placement: CardPlacement, _ canvas: CGSize, versus: Bool = true) -> NextOpponentLayout? {
        NextOpponentLayout.resolve(canvas: canvas, trackerPanel: nil, rightLimit: 100, hasStatusRow: true,
                                   hasVersusRow: versus, hasTribesRow: true, custom: placement)
    }

    @Test func roundTripsAtTheSameWindow() {
        let canvas = CGSize(width: 1920, height: 1080)
        let placement = CardPlacement.make(origin: CGPoint(x: 600, y: 300), scale: 1.1, canvas: canvas)
        let layout = custom(placement, canvas)
        #expect(layout?.origin == CGPoint(x: 600, y: 300))
        #expect(abs((layout?.scale ?? 0) - 1.1) < 0.0001)
    }

    @Test func followsTheWindowAtOtherShapes() {
        let placement = CardPlacement.make(origin: CGPoint(x: 960, y: 270), scale: 1.0, canvas: CGSize(width: 1920, height: 1080))
        for canvas in [CGSize(width: 1440, height: 900), CGSize(width: 1024, height: 768), CGSize(width: 3840, height: 2160)] {
            guard let layout = custom(placement, canvas) else { Issue.record("no card at \(canvas)"); continue }
            // Same fractions of the window, scale proportional to its height (clamped).
            #expect(abs(layout.origin.x - canvas.width * 0.5) < 0.5)
            #expect(abs(layout.origin.y - canvas.height * 0.25) < 0.5)
            let wanted = min(max(canvas.height / 1080, 0.7), 1.6)
            #expect(abs(layout.scale - wanted) < 0.0001)
        }
    }

    @Test func scaleIsClamped() {
        let canvas = CGSize(width: 1920, height: 1080)
        #expect(CardPlacement.make(origin: .zero, scale: 3, canvas: canvas).scale(in: canvas) == 1.6)
        #expect(CardPlacement.make(origin: .zero, scale: 0.2, canvas: canvas).scale(in: canvas) == 0.7)
    }

    @Test func aSpotPastTheEdgeIsPulledBackInside() {
        let canvas = CGSize(width: 1920, height: 1080)
        let layout = custom(CardPlacement(x: 0.98, y: 0.97, size: 0.25), canvas)
        #expect(layout != nil)
        if let layout {
            #expect(layout.origin.x + layout.width <= canvas.width)
            #expect(layout.origin.y + layout.height <= canvas.height)
            #expect(layout.origin.x >= 0 && layout.origin.y >= 0)
        }
    }

    @Test func aCardTooBigForTheWindowFallsBackToAutomatic() {
        let tiny = CGSize(width: 400, height: 250)
        let placement = CardPlacement(x: 0.1, y: 0.1, size: 1.6)
        #expect(NextOpponentLayout.custom(placement, canvas: tiny, hasStatusRow: true, hasVersusRow: true, hasTribesRow: true) == nil)
        let layout = custom(placement, CGSize(width: 1920, height: 1080), versus: true)
        #expect(layout?.fixed != nil)
    }

    @Test func rowsGiveWayInsteadOfTheUsersScale() {
        // A big card in a short window keeps its scale and drops the versus line, then tribes.
        let canvas = CGSize(width: 1600, height: 450)
        let layout = custom(CardPlacement.make(origin: CGPoint(x: 10, y: 10), scale: 1.3, canvas: canvas), canvas)
        #expect(layout != nil)
        #expect(layout?.rows.showsVersus == false)
        #expect(abs((layout?.scale ?? 0) - 1.3) < 0.0001)
    }

    @Test func shapesAndPerShapeStorage() {
        #expect(CardPlacements.shape(of: CGSize(width: 1920, height: 1080)) == "16:9")
        #expect(CardPlacements.shape(of: CGSize(width: 1440, height: 900)) == "16:10")
        #expect(CardPlacements.shape(of: CGSize(width: 1024, height: 768)) == "4:3")
        var saved = CardPlacements()
        let wide = CardPlacement(x: 0.5, y: 0.5, size: 0.2)
        let mac = CardPlacement(x: 0.1, y: 0.6, size: 0.25)
        saved.save(wide, for: CGSize(width: 1920, height: 1080))
        saved.save(mac, for: CGSize(width: 1440, height: 900))
        #expect(saved.placement(for: CGSize(width: 3840, height: 2160)) == wide)
        #expect(saved.placement(for: CGSize(width: 2560, height: 1600)) == mac)
        // A shape never placed borrows the last spot.
        #expect(saved.placement(for: CGSize(width: 1024, height: 768)) == mac)
    }

    @Test func storesAndResets() {
        let defaults = UserDefaults(suiteName: "CardPlacementTests-\(UUID().uuidString)")!
        var saved = CardPlacements()
        saved.save(CardPlacement(x: 0.2, y: 0.3, size: 0.2), for: CGSize(width: 1920, height: 1080))
        saved.store(defaults)
        #expect(CardPlacements.load(defaults) == saved)
        CardPlacements().store(defaults)
        #expect(CardPlacements.load(defaults).isEmpty)
        #expect(defaults.data(forKey: CardPlacements.defaultsKey) == nil)
    }
}
