import CoreGraphics
import Foundation
import Testing
@testable import HSBGMacOverlay

@Suite struct MinionZoomGeometryTests {
    private let board = CGRect(x: 14, y: 100, width: 242, height: 30)

    @Test func tileFramesFollowOriginAndScale() {
        let frames = MinionZoomGeometry.tileFrames(board: board, count: 3, origin: CGPoint(x: 10, y: 200), scale: 2)
        #expect(frames.count == 3)
        #expect(frames[0] == CGRect(x: 10 + 28, y: 200 + 200, width: 64, height: 60))
        // Next tile: one tile plus the spacing to the right, scaled.
        #expect(frames[1].minX == frames[0].minX + (32 + 3) * 2)
    }

    @Test func sevenTilesFillTheRowExactly() {
        let frames = MinionZoomGeometry.tileFrames(board: board, count: 7, origin: .zero, scale: 1)
        #expect(frames.last?.maxX == board.maxX)
    }

    @Test func hitTestFindsTheTileAndIgnoresGapsAndOutside() {
        let frames = MinionZoomGeometry.tileFrames(board: board, count: 3, origin: .zero, scale: 1)
        #expect(MinionZoomGeometry.hitIndex(at: CGPoint(x: 14 + 5, y: 110), in: frames) == 0)
        #expect(MinionZoomGeometry.hitIndex(at: CGPoint(x: 14 + 35 + 5, y: 110), in: frames) == 1)
        #expect(MinionZoomGeometry.hitIndex(at: CGPoint(x: 14 + 33, y: 110), in: frames) == nil)
        #expect(MinionZoomGeometry.hitIndex(at: CGPoint(x: 14 + 5, y: 90), in: frames) == nil)
        #expect(MinionZoomGeometry.hitIndex(at: CGPoint(x: 5, y: 110), in: []) == nil)
    }

    @Test func screenPointConvertsToTopLeftCanvas() {
        let frame = CGRect(x: 100, y: 50, width: 1000, height: 600)
        // Top-left corner of the canvas in Cocoa coordinates is (100, 650).
        #expect(MinionZoomGeometry.canvasPoint(fromScreen: CGPoint(x: 100, y: 650), canvasCocoaFrame: frame) == .zero)
        #expect(MinionZoomGeometry.canvasPoint(fromScreen: CGPoint(x: 300, y: 600), canvasCocoaFrame: frame) == CGPoint(x: 200, y: 50))
    }

    @Test func panelSizeKeepsTheImageRatioAndCapsItsHeight() {
        let normal = MinionZoomGeometry.panelSize(imageSize: CGSize(width: 100, height: 100))
        #expect(normal.width == MinionZoomGeometry.panelWidth)
        #expect(normal.height == 156 + MinionZoomGeometry.nameHeight + 12)
        let tall = MinionZoomGeometry.panelSize(imageSize: CGSize(width: 100, height: 1000))
        #expect(tall.height == MinionZoomGeometry.maxImageHeight + MinionZoomGeometry.nameHeight + 12)
        #expect(MinionZoomGeometry.panelSize(imageSize: nil).height == MinionZoomGeometry.textOnlyHeight)
    }

    @Test func panelGoesRightOfTheCardWhenThereIsRoom() {
        let card = CGRect(x: 10, y: 300, width: 270, height: 260)
        let tile = CGRect(x: 24, y: 450, width: 32, height: 30)
        let size = CGSize(width: 168, height: 200)
        let spot = MinionZoomGeometry.placement(card: card, tile: tile, size: size, canvas: CGSize(width: 1280, height: 780))
        #expect(spot.minX == card.maxX + MinionZoomGeometry.gap)
        #expect(spot.midY == tile.midY)
        #expect(!spot.intersects(card))
    }

    @Test func panelStaysInsideTheCanvasVertically() {
        let card = CGRect(x: 10, y: 500, width: 270, height: 260)
        let tile = CGRect(x: 24, y: 740, width: 32, height: 30)
        let canvas = CGSize(width: 1280, height: 780)
        let spot = MinionZoomGeometry.placement(card: card, tile: tile, size: CGSize(width: 168, height: 300), canvas: canvas)
        #expect(spot.maxY == canvas.height)
        let high = MinionZoomGeometry.placement(card: card, tile: CGRect(x: 24, y: 2, width: 32, height: 30),
                                                size: CGSize(width: 168, height: 300), canvas: canvas)
        #expect(high.minY == 0)
    }

    @Test func panelFallsToTheLeftThenAboveWhenTheRightIsTaken() {
        let size = CGSize(width: 168, height: 200)
        let canvas = CGSize(width: 600, height: 780)
        let rightCard = CGRect(x: 400, y: 400, width: 180, height: 260)
        let left = MinionZoomGeometry.placement(card: rightCard, tile: CGRect(x: 410, y: 500, width: 32, height: 30), size: size, canvas: canvas)
        #expect(left.maxX == rightCard.minX - MinionZoomGeometry.gap)
        #expect(!left.intersects(rightCard))

        let wideCard = CGRect(x: 10, y: 400, width: 580, height: 260)
        let above = MinionZoomGeometry.placement(card: wideCard, tile: CGRect(x: 300, y: 500, width: 32, height: 30), size: size, canvas: canvas)
        #expect(above.maxY <= wideCard.minY)
        #expect(CGRect(origin: .zero, size: canvas).contains(above))
    }
}

@Suite struct MinionZoomSettingTests {
    @Test func defaultsOnAndFollowsTheStoredValue() {
        let defaults = UserDefaults(suiteName: "MinionZoomSettingTests-\(UUID().uuidString)")!
        #expect(SettingsModel.zoomsMinionsOnHover(defaults))
        defaults.set(false, forKey: SettingsKey.zoomsMinionsOnHover)
        #expect(!SettingsModel.zoomsMinionsOnHover(defaults))
    }
}
