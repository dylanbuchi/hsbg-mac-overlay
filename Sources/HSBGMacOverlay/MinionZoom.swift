import AppKit
import SwiftUI

/// Where the minion thumbnails of the NEXT OPPONENT card are, in the game window's coordinates
/// (top-left origin), plus the card itself. Reported by the card, read by the hover monitor.
struct MinionTiles: Equatable {
    var card: CGRect
    var frames: [CGRect]
    var minions: [BoardMinion]

    static let empty = MinionTiles(card: .zero, frames: [], minions: [])
}

/// The NEXT OPPONENT card's frame in game-window coordinates, for placing it by hand.
struct CardFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct MinionTilesKey: PreferenceKey {
    static let defaultValue = MinionTiles.empty
    static func reduce(value: inout MinionTiles, nextValue: () -> MinionTiles) {
        let next = nextValue()
        if !next.frames.isEmpty { value = next }
    }
}

extension NSWindow.Level {
    /// The overlay over the game window. It is brought to the front every half second.
    static let gameOverlay = NSWindow.Level.statusBar
    /// The minion zoom and the card's handles: one level up, so re-fronting the overlay never hides them under
    /// the card they sit on.
    static let aboveGameOverlay = NSWindow.Level(rawValue: NSWindow.Level.gameOverlay.rawValue + 1)
    /// The minion zoom: above the handles too, since it opens over the card.
    static let minionZoom = NSWindow.Level(rawValue: NSWindow.Level.aboveGameOverlay.rawValue + 1)
}

/// Pure geometry for the hover zoom: tile frames, hit-testing, where the zoom panel goes.
enum MinionZoomGeometry {
    static let tileSize = CGSize(width: 32, height: 30)
    static let tileSpacing: CGFloat = 3
    static let gap: CGFloat = 8
    static let panelWidth: CGFloat = 168
    static let maxImageHeight: CGFloat = 240
    static let nameHeight: CGFloat = 22
    static let inset: CGFloat = 6
    static let textOnlyHeight: CGFloat = 40

    /// Tile frames in canvas coordinates, for a board row at `board` (card space, unscaled)
    /// on a card drawn at `origin` and `scale`.
    static func tileFrames(board: CGRect, count: Int, origin: CGPoint, scale: CGFloat) -> [CGRect] {
        (0..<max(count, 0)).map { index in
            let x = board.minX + CGFloat(index) * (tileSize.width + tileSpacing)
            return CGRect(x: origin.x + x * scale, y: origin.y + board.minY * scale,
                          width: tileSize.width * scale, height: tileSize.height * scale)
        }
    }

    /// The tile under `point`, if any. The gaps between tiles count as nothing.
    static func hitIndex(at point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Screen point (Cocoa: origin bottom-left) to canvas point (origin top-left).
    static func canvasPoint(fromScreen point: CGPoint, canvasCocoaFrame frame: CGRect) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    static func panelSize(imageSize: CGSize?) -> CGSize {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: panelWidth, height: textOnlyHeight)
        }
        let imageWidth = panelWidth - inset * 2
        let imageHeight = min(imageWidth * imageSize.height / imageSize.width, maxImageHeight)
        return CGSize(width: panelWidth, height: imageHeight + nameHeight + inset * 2)
    }

    /// The zoom panel's frame in canvas coordinates: above the hovered minion, centered on it and kept inside
    /// the canvas; below it when there is no room above. Never beside the card, where it would cover the
    /// player names on the leaderboard portraits.
    static func placement(tile: CGRect, size: CGSize, canvas: CGSize) -> CGRect {
        let x = max(0, min(tile.midX - size.width / 2, canvas.width - size.width))
        let above = tile.minY - gap - size.height
        let y = above >= 0 ? above : min(tile.maxY + gap, canvas.height - size.height)
        return CGRect(x: x, y: max(0, y), width: size.width, height: size.height)
    }
}

/// The enlarged minion: its card render and its name.
struct MinionZoomView: View {
    let minion: BoardMinion
    let image: NSImage?

    var body: some View {
        let size = MinionZoomGeometry.panelSize(imageSize: image?.size)
        VStack(spacing: 4) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size.width - MinionZoomGeometry.inset * 2,
                           height: size.height - MinionZoomGeometry.nameHeight - MinionZoomGeometry.inset * 2)
            }
            Text(verbatim: minion.isGolden ? "Golden \(minion.name)" : minion.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EdgeInkPalette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(height: image == nil ? nil : MinionZoomGeometry.nameHeight - 4)
        }
        .padding(MinionZoomGeometry.inset)
        .frame(width: size.width, height: size.height)
        .background(EdgeInkPalette.cardBackground.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(minion.isGolden ? EdgeInkPalette.leaderGold : Color.white.opacity(0.18), lineWidth: minion.isGolden ? 2 : 1))
    }
}

/// Watches the mouse and shows the zoom panel over the minion under it. The overlay is click-through, so
/// hover comes from mouse-moved monitors (reading the position needs no extra permission); the zoom panel
/// is click-through and nonactivating too, so the game never loses a click or focus.
@MainActor
final class MinionZoomController {
    static let delay: Duration = .milliseconds(150)

    private let model: OverlayModel
    private let cardArt: CardArtLoader
    /// The game window (or demo canvas) in screen coordinates; nil when the overlay is not shown.
    private let canvasFrame: () -> CGRect?
    private let isEnabled: () -> Bool
    private var monitors: [Any] = []
    private var panel: NSPanel?
    private var shownIndex: Int?
    private var pendingIndex: Int?
    private var pendingTask: Task<Void, Never>?

    init(model: OverlayModel, cardArt: CardArtLoader = .shared, canvasFrame: @escaping () -> CGRect?,
         isEnabled: @escaping () -> Bool = { SettingsModel.zoomsMinionsOnHover() }) {
        self.model = model
        self.cardArt = cardArt
        self.canvasFrame = canvasFrame
        self.isEnabled = isEnabled
    }

    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        }) { monitors.append(global) }
        // Events inside this app's own windows (the demo) never reach the global monitor.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            Task { @MainActor in self?.mouseMoved() }
            return event
        }) { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hide()
    }

    /// Called on a timer: hides the zoom when the card or the window went away without a mouse move.
    func refresh() {
        if shownIndex != nil || pendingIndex != nil { mouseMoved() }
    }

    func hide() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingIndex = nil
        shownIndex = nil
        panel?.orderOut(nil)
    }

    private func currentHit() -> Int? {
        let tiles = model.minionTiles
        guard !tiles.frames.isEmpty, !model.isEditingCard, !model.isDraggingCard, isEnabled(),
              let frame = canvasFrame() else { return nil }
        let point = MinionZoomGeometry.canvasPoint(fromScreen: NSEvent.mouseLocation, canvasCocoaFrame: frame)
        // The card's move and resize handles win over a minion under them.
        if CardHandleGeometry.isOnHandle(point, card: tiles.card) { return nil }
        return MinionZoomGeometry.hitIndex(at: point, in: tiles.frames)
    }

    private func mouseMoved() {
        guard let index = currentHit() else {
            if shownIndex != nil || pendingIndex != nil { hide() }
            return
        }
        if index == shownIndex || index == pendingIndex { return }
        pendingTask?.cancel()
        pendingIndex = index
        if shownIndex != nil {
            // Sliding from one minion to the next: no delay, no flicker.
            show(index)
            return
        }
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let self, self.currentHit() == index else { return }
            self.show(index)
        }
    }

    private func show(_ index: Int) {
        let tiles = model.minionTiles
        guard index < tiles.frames.count, index < tiles.minions.count, let frame = canvasFrame() else { hide(); return }
        let minion = tiles.minions[index]
        let image = cardArt.image(for: minion.name)
        let size = MinionZoomGeometry.panelSize(imageSize: image?.size)
        let spot = MinionZoomGeometry.placement(tile: tiles.frames[index], size: size, canvas: frame.size)
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: MinionZoomView(minion: minion, image: image))
        panel.setFrame(NSRect(x: frame.minX + spot.minX, y: frame.maxY - spot.maxY, width: spot.width, height: spot.height),
                       display: true)
        panel.orderFrontRegardless()
        pendingTask = nil
        pendingIndex = nil
        shownIndex = index
    }

    func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .minionZoom
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        self.panel = panel
        return panel
    }
}
