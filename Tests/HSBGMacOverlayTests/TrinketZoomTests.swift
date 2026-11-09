import AppKit
import SwiftUI
import XCTest
@testable import HSBGMacOverlay

private final class TilesBox: @unchecked Sendable { var value = MinionTiles.empty }

@MainActor
final class TrinketZoomTests: XCTestCase {
    func testMergedTilesKeepBoardAndTrinkets() {
        var value = MinionTiles.empty
        let board = MinionTiles(card: CGRect(x: 0, y: 0, width: 10, height: 10), frames: [CGRect(x: 1, y: 5, width: 1, height: 1)],
                                minions: [BoardMinion(cardID: "a", name: "A", isGolden: false)])
        let trinket = MinionTiles(card: board.card, frames: [CGRect(x: 8, y: 1, width: 1, height: 1)],
                                  minions: [BoardMinion(cardID: "trinket:1", name: "T", isGolden: false)])
        MinionTilesKey.reduce(value: &value) { board }
        MinionTilesKey.reduce(value: &value) { .empty }
        MinionTilesKey.reduce(value: &value) { trinket }
        XCTAssertEqual(value.minions.map(\.name), ["A", "T"])
        XCTAssertEqual(value.frames.count, 2)
    }

    func testTrinketTilesAreHoverableWhereTheyAreDrawn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trinket-zoom-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let cache = CardArtCache(directory: dir)
        cache.storeTrinketNames([130835: "Lens Case", 131303: "Magicfin Sticker"])
        let loader = CardArtLoader(cache: cache, fetch: { _ in throw URLError(.notConnectedToInternet) })

        let lobby = DemoScenario.lobby(atGameStart: false).players
        let player = try XCTUnwrap(DemoScenario.nextOpponent)
        let content = NextOpponentContent(player: player, lobby: lobby, currentTurn: 10)
        let layout = try XCTUnwrap(NextOpponentLayout.resolve(
            canvas: CGSize(width: 1920, height: 1080), trackerPanel: nil, rightLimit: nil,
            hasStatusRow: content.hasStatusRow, hasVersusRow: content.hasFightWithYou, hasTribesRow: content.tribesRow != nil))
        let box = TilesBox()
        let view = NextOpponentCard(content: content, layout: layout, cardArt: loader)
            .onPreferenceChange(MinionTilesKey.self) { box.value = $0 }
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let tiles = box.value
        let names = tiles.minions.map(\.name)
        XCTAssertEqual(names.filter { ["Lens Case", "Magicfin Sticker"].contains($0) }, ["Lens Case", "Magicfin Sticker"])
        XCTAssertEqual(names.count, content.boardMinions.count + 2)
        let trinketIndices = tiles.minions.indices.filter { tiles.minions[$0].cardID.hasPrefix("trinket:") }
        XCTAssertEqual(trinketIndices.count, 2)
        let trinkets = trinketIndices.map { tiles.frames[$0] }
        let board = try XCTUnwrap(tiles.minions.indices.first { !tiles.minions[$0].cardID.hasPrefix("trinket:") }.map { tiles.frames[$0] })
        let card = CGRect(origin: layout.origin, size: CGSize(width: layout.width, height: layout.height))
        for frame in trinkets {
            XCTAssertTrue(card.contains(frame), "trinket \(frame) outside card \(card)")
            XCTAssertLessThan(frame.maxY, board.minY, "trinkets sit in the header, above the board")
            XCTAssertGreaterThan(frame.minX, card.midX, "trinkets sit on the right")
            XCTAssertFalse(CardHandleGeometry.isOnHandle(CGPoint(x: frame.midX, y: frame.midY), card: card))
            XCTAssertEqual(frame.width, TrinketTiles.size.width * layout.scale, accuracy: 0.5)
        }
        XCTAssertGreaterThan(trinkets[1].minX, trinkets[0].maxX)
    }
}
