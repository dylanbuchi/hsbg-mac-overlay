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

/// The card must degrade, not vanish, when HSTracker's panel is tall or the window is narrow.
@Suite struct NextOpponentDegradeTests {
    private func layout(canvas: CGSize, panel: CGRect?, rightLimit: CGFloat? = nil) -> NextOpponentLayout? {
        NextOpponentLayout.resolve(canvas: canvas, trackerPanel: panel, rightLimit: rightLimit, hasStatusRow: true,
                                   hasVersusRow: true, hasTribesRow: true)
    }

    /// Demo window of about 1900x1150 with the tallest fake panel: the card was hidden because even
    /// the smallest scale (0.6) was 2 points wider than the room left of the portraits.
    @Test func demoGeometryShowsTheCardInsteadOfHidingIt() {
        let canvas = CGSize(width: 1900, height: 1150)
        let edge = LeaderboardLayout(canvasSize: canvas, nextOpponentPlace: DemoScenario.nextOpponentPlace).labelsLeftEdge
        let panel = DemoPanel.tall.frame(in: canvas)
        let found = layout(canvas: canvas, panel: panel, rightLimit: edge)
        #expect(found != nil)
        if let found {
            #expect(found.origin.x + found.width <= edge + 0.001)
            #expect(found.origin.y >= (panel?.maxY ?? 0))
        }
    }

    @Test func everyDemoPanelAndWindowSizeKeepsTheCard() {
        for height in stride(from: 1000.0, through: 1300.0, by: 50.0) {
            for width in [height * 16 / 9, height * 1.65] {
                let canvas = CGSize(width: width, height: height)
                let edge = LeaderboardLayout(canvasSize: canvas, nextOpponentPlace: DemoScenario.nextOpponentPlace).labelsLeftEdge
                for panel in DemoPanel.allCases {
                    #expect(layout(canvas: canvas, panel: panel.frame(in: canvas), rightLimit: edge) != nil,
                            "hidden at \(canvas) with \(panel)")
                }
            }
        }
    }

    @Test func rowsAreDroppedInOrderAsThePanelGrows() {
        let canvas = CGSize(width: 2400, height: 1350)
        var lost: [String] = []
        for bottom in stride(from: 0.3, through: 0.9, by: 0.01) {
            let panel = CGRect(x: 0, y: 40, width: 360, height: canvas.height * bottom - 40)
            guard let found = layout(canvas: canvas, panel: panel) else { continue }
            let rows = found.rows
            for (name, shown) in [("versus", rows.showsVersus), ("status", rows.showsStatus), ("tribes", rows.showsTribes)]
            where !shown && !lost.contains(name) { lost.append(name) }
        }
        // Versus goes before health and triples, which go before the tribes line.
        let order = ["versus", "status", "tribes"].filter(lost.contains)
        #expect(lost == order, "lost \(lost)")
        #expect(lost.contains("versus"))
    }

    /// The default demo (16:9 canvas of a large window, no fake panel) shows every row.
    @Test func largeDemoCanvasShowsEveryRow() {
        let canvas = CGSize(width: 1960, height: 1102.5)
        let edge = LeaderboardLayout(canvasSize: canvas, nextOpponentPlace: DemoScenario.nextOpponentPlace).labelsLeftEdge
        let rows = layout(canvas: canvas, panel: nil, rightLimit: edge)?.rows
        #expect(rows?.showsStatus == true && rows?.showsVersus == true && rows?.showsTribes == true && rows?.showsTierPace == true)
    }

    @Test func aTooTallPanelFallsBackToTheBottomOfTheWindow() {
        let canvas = CGSize(width: 1920, height: 1080)
        let panel = CGRect(x: 0, y: 30, width: 260, height: 1000)
        let found = layout(canvas: canvas, panel: panel)
        #expect(found != nil)
        if let found { #expect(found.origin.y + found.height <= canvas.height) }
    }
}
