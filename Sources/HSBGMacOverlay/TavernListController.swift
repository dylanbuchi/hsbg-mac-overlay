import AppKit
import Combine
import SwiftUI

/// A click on a tier's shield opens its list and keeps it open; a second click on the same shield closes it
/// (a click on another shield switches). While a list is open, the card under the mouse shows larger. The
/// panels for every tier are built once per game (and when the window size changes), so a click only orders
/// one in and the others out. It only watches mouse events (no extra permission) and every panel ignores the
/// mouse, so the click still reaches the game, where the strip sits on the empty curtain beside the board.
@MainActor
final class TavernListController {
    /// How long a row stays hovered before its art is fetched, so sweeping over the list costs no requests.
    static let artDelay: Duration = .milliseconds(250)

    private let model: OverlayModel
    private let canvasFrame: () -> CGRect?
    private let cardArt: CardArtLoader
    private var monitors: [Any] = []
    private var panels: [Int: NSPanel] = [:]
    private var rows: [Int: [TavernRowHit]] = [:]
    private var builtFor: (sheets: [TavernSheet], size: CGSize)?
    private var shownTier: Int?
    /// The open list in game-window coordinates.
    private var shownSpot: CGRect?
    /// The game window the open list was placed for, to follow it when it moves.
    private var shownCanvas: CGRect?
    private var zoomPanel: NSPanel?
    private var zoomedCard: String?
    private var artTask: Task<Void, Never>?
    private var sheetsWatch: AnyCancellable?
    /// `HSBG_TAVERN_TIMING=1` prints hover-to-paint times to stderr (tiers and milliseconds only).
    private let logsTiming = ProcessInfo.processInfo.environment["HSBG_TAVERN_TIMING"] == "1"

    init(model: OverlayModel, cardArt: CardArtLoader = .shared, canvasFrame: @escaping () -> CGRect?) {
        self.model = model
        self.cardArt = cardArt
        self.canvasFrame = canvasFrame
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handle: @Sendable (NSEvent.EventType) -> Void = { [weak self] type in
            MainActor.assumeIsolated {
                if type == .leftMouseDown { self?.mouseDown() } else { self?.mouseMoved() }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown],
                                                          handler: { handle($0.type) }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown], handler: { event in
            handle(event.type)
            return event
        }) { monitors.append(local) }
        // New sheets (a new game, the lobby's tribes): rebuild the panels now, not on the first hover.
        sheetsWatch = model.$tavernSheets.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.prepare()
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        sheetsWatch = nil
        hide()
    }

    /// On the position timer: closes the list when the strip went away (combat, game over), keeps the panels
    /// built, and moves an open list with the game window.
    func refresh() {
        guard model.showsTavernStrip, let frame = canvasFrame() else {
            if shownTier != nil { hide() }
            return
        }
        prepare()
        if let shownTier, frame != shownCanvas { show(shownTier, canvas: frame) }
    }

    func hide() {
        hideCard()
        if let shownTier { panels[shownTier]?.orderOut(nil) }
        shownTier = nil
        shownSpot = nil
        shownCanvas = nil
        if model.openTavernTier != nil { model.openTavernTier = nil }
    }

    private func mouseDown() {
        guard model.showsTavernStrip, let frame = canvasFrame() else { return }
        let point = MinionZoomGeometry.canvasPoint(fromScreen: NSEvent.mouseLocation, canvasCocoaFrame: frame)
        guard let tier = TavernStripGeometry.hitTier(at: point, in: model.tavernStripTiles) else { return }
        if let next = TavernStripGeometry.tierAfterClick(on: tier, open: shownTier) {
            show(next, canvas: frame)
        } else {
            hide()
        }
    }

    /// Only the card zoom follows the mouse; the list itself stays until clicked shut.
    private func mouseMoved() {
        guard let tier = shownTier, let spot = shownSpot, let frame = canvasFrame() else { return }
        let point = MinionZoomGeometry.canvasPoint(fromScreen: NSEvent.mouseLocation, canvasCocoaFrame: frame)
        guard spot.contains(point) else { hideCard(); return }
        let local = CGPoint(x: point.x - spot.minX, y: point.y - spot.minY)
        guard let row = rows[tier]?.first(where: { $0.frame.contains(local) }) else { hideCard(); return }
        showCard(row.card, row: row.frame.offsetBy(dx: spot.minX, dy: spot.minY), list: spot, canvas: frame)
    }

    func show(_ tier: Int, canvas frame: CGRect) {
        let start = DispatchTime.now()
        prepare()
        guard let panel = panels[tier], let strip = stripFrame() else { hide(); return }
        if let shownTier, shownTier != tier { panels[shownTier]?.orderOut(nil) }
        let spot = TavernStripGeometry.placement(strip: strip, size: panel.frame.size, canvas: frame.size)
        panel.setFrameOrigin(NSPoint(x: frame.minX + spot.minX, y: frame.maxY - spot.maxY))
        panel.orderFrontRegardless()
        shownTier = tier
        shownSpot = spot
        shownCanvas = frame
        model.openTavernTier = tier
        if logsTiming {
            panel.displayIfNeeded()
            CATransaction.flush()
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            FileHandle.standardError.write(Data(String(format: "tavern hover tier %d: %.1f ms, %d rows\n", tier, ms,
                                                       rows[tier]?.count ?? 0).utf8))
            // Demo checks only: a PNG of the panel, drawn by the app itself (no screen recording).
            if let directory = ProcessInfo.processInfo.environment["HSBG_TAVERN_SNAPSHOT"], let view = panel.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("tier-\(tier).png"))
            }
        }
    }

    /// The card under the mouse, larger: its art when cached, else its name until the art arrives.
    private func showCard(_ card: PoolCard, row: CGRect, list: CGRect, canvas frame: CGRect) {
        guard zoomedCard != card.id else { return }
        zoomedCard = card.id
        artTask?.cancel()
        artTask = nil
        drawCard(card, row: row, list: list, canvas: frame)
        guard cardArt.image(for: card.name) == nil else { return }
        artTask = Task { [weak self] in
            try? await Task.sleep(for: Self.artDelay)
            guard !Task.isCancelled, let self, self.zoomedCard == card.id else { return }
            await self.cardArt.ensure([card.name])
            guard !Task.isCancelled, self.zoomedCard == card.id, self.cardArt.image(for: card.name) != nil,
                  let frame = self.canvasFrame() else { return }
            self.drawCard(card, row: row, list: list, canvas: frame)
        }
    }

    private func drawCard(_ card: PoolCard, row: CGRect, list: CGRect, canvas frame: CGRect) {
        let image = cardArt.image(for: card.name)
        let size = MinionZoomGeometry.panelSize(imageSize: image?.size)
        let spot = TavernStripGeometry.cardPlacement(row: row, list: list, size: size, canvas: frame.size)
        let panel = zoomPanel ?? makePanel(level: .tavernCardZoom)
        zoomPanel = panel
        panel.contentView = NSHostingView(rootView: MinionZoomView(
            minion: BoardMinion(cardID: card.id, name: card.name, isGolden: false), image: image))
        panel.setFrame(NSRect(x: frame.minX + spot.minX, y: frame.maxY - spot.maxY, width: spot.width, height: spot.height),
                       display: true)
        panel.orderFrontRegardless()
    }

    private func hideCard() {
        artTask?.cancel()
        artTask = nil
        zoomedCard = nil
        zoomPanel?.orderOut(nil)
    }

    private func stripFrame() -> CGRect? {
        let frames = model.tavernStripTiles.map(\.frame)
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Builds one hidden panel per tier when the sheets or the window size changed.
    private func prepare() {
        let sheets = model.tavernSheets
        guard let frame = canvasFrame(), frame.width > 0, let strip = stripFrame() ?? expectedStrip(frame.size) else { return }
        if let builtFor, builtFor.sheets == sheets, builtFor.size == frame.size { return }
        let start = DispatchTime.now()
        hide()
        panels.values.forEach { $0.orderOut(nil) }
        let scale = TavernStripGeometry.scale(canvas: frame.size)
        let columnWidth = TavernStripGeometry.columnWidth(canvas: frame.size, scale: scale)
        let maxHeight = TavernStripGeometry.maxListHeight(strip: strip, canvas: frame.size)
        var built: [Int: NSPanel] = [:]
        rows = [:]
        for sheet in sheets {
            let panel = panels[sheet.tier] ?? makePanel(level: .minionZoom)
            let tier = sheet.tier
            let view = NSHostingView(rootView: TavernSheetView(sheet: sheet, scale: scale, columnWidth: columnWidth,
                                                                maxHeight: maxHeight) { [weak self] hits in
                self?.rows[tier] = hits
            })
            let size = view.fittingSize
            panel.contentView = view
            panel.setContentSize(size)
            view.layoutSubtreeIfNeeded()
            built[sheet.tier] = panel
        }
        panels = built
        builtFor = (sheets, frame.size)
        if logsTiming, !sheets.isEmpty {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            FileHandle.standardError.write(Data(String(format: "tavern panels built: %d tiers in %.1f ms\n", sheets.count, ms).utf8))
        }
    }

    /// The strip as it will be drawn, for building the panels before it first appears.
    private func expectedStrip(_ canvas: CGSize) -> CGRect? {
        let frames = TavernStripGeometry.tiles(tiers: model.tavernSheets.map(\.tier), canvas: canvas).map(\.frame)
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    private func makePanel(level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        return panel
    }
}
