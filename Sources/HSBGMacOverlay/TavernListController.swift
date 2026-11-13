import AppKit
import Combine
import SwiftUI

/// A click on a tier's shield opens its list and keeps it open; a second click on the same shield closes it
/// (a click on another shield switches). The funnel left of tier 1 drops the filter down; its choices
/// toggle with a click and every list follows. While a list is open, the card under the mouse shows larger.
/// Each tier's panel is built ahead (once per game, window size and filter), so a click only orders one in.
/// It only watches mouse events (no extra permission) and every panel ignores the mouse, so the click still
/// reaches the game, where the strip and the filter sit on the empty curtain beside the board.
@MainActor
final class TavernListController {
    /// How long a row stays hovered before its art is fetched, so sweeping over the list costs no requests.
    static let artDelay: Duration = .milliseconds(250)

    private struct Built: Equatable {
        var sheet: TavernSheet
        var size: CGSize
        var summary: String?
    }

    private let model: OverlayModel
    private let canvasFrame: () -> CGRect?
    private let cardArt: CardArtLoader
    private var monitors: [Any] = []
    private var panels: [Int: NSPanel] = [:]
    private var built: [Int: Built] = [:]
    private var rows: [Int: [TavernRowHit]] = [:]
    private var shownTier: Int?
    /// The open list in game-window coordinates.
    private var shownSpot: CGRect?
    /// The game window the open list or filter was placed for, to follow it when it moves.
    private var shownCanvas: CGRect?
    private var filterPanel: NSPanel?
    private var filterSpot: CGRect?
    private var filterHits: [TavernFilterHit] = []
    private var zoomPanel: NSPanel?
    private var zoomedCard: String?
    private var artTask: Task<Void, Never>?
    private var watches: Set<AnyCancellable> = []
    private var artLearnedFor: [TavernSheet]?
    /// `HSBG_TAVERN_TIMING=1` prints open times to stderr (tiers and milliseconds only).
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
        // New sheets (a new game, the lobby's tribes): rebuild the panels now, not on the first click.
        model.$tavernSheets.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.prepare()
        }.store(in: &watches)
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        watches = []
        hide()
    }

    /// On the position timer: closes everything when the strip went away (combat, game over), builds one
    /// stale panel ahead, and moves an open list or filter with the game window.
    func refresh() {
        guard model.showsTavernStrip, let frame = canvasFrame() else {
            if shownTier != nil || model.tavernFilterOpen { hide() }
            return
        }
        prepare(atMost: 1)
        guard frame != shownCanvas else { return }
        if let shownTier { show(shownTier, canvas: frame) }
        if model.tavernFilterOpen { showFilter(canvas: frame) }
    }

    func hide() {
        hideList()
        hideFilter()
    }

    private func hideList() {
        hideCard()
        if let shownTier { panels[shownTier]?.orderOut(nil) }
        shownTier = nil
        shownSpot = nil
        if model.openTavernTier != nil { model.openTavernTier = nil }
    }

    private func hideFilter() {
        filterPanel?.orderOut(nil)
        filterSpot = nil
        if model.tavernFilterOpen { model.tavernFilterOpen = false }
    }

    private func mouseDown() {
        guard model.showsTavernStrip, let frame = canvasFrame() else { return }
        let point = MinionZoomGeometry.canvasPoint(fromScreen: NSEvent.mouseLocation, canvasCocoaFrame: frame)
        let tiles = model.tavernStripTiles
        if let button = TavernStripGeometry.filterFrame(tiles: tiles), button.contains(point) {
            if model.tavernFilterOpen {
                hideFilter()
            } else {
                hideList()
                showFilter(canvas: frame)
            }
            return
        }
        if let spot = filterSpot, spot.contains(point) {
            let local = CGPoint(x: point.x - spot.minX, y: point.y - spot.minY)
            guard let hit = filterHits.first(where: { $0.frame.contains(local) }) else { return }
            switch hit.item {
            case .kind(let kind): model.tavernFilter.toggle(kind)
            case .key(let key): model.tavernFilter.toggle(key)
            case .clear: model.tavernFilter = TavernFilter()
            }
            showFilter(canvas: frame)
            return
        }
        if let tier = TavernStripGeometry.hitTier(at: point, in: tiles) {
            hideFilter()
            if let next = TavernStripGeometry.tierAfterClick(on: tier, open: shownTier) {
                show(next, canvas: frame)
            } else {
                hideList()
            }
            return
        }
        // A click anywhere else puts the filter away; an open list stays until its shield is clicked.
        if model.tavernFilterOpen { hideFilter() }
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
        build(tier, canvas: frame)
        guard let panel = panels[tier], let strip = stripFrame() else { hideList(); return }
        if let shownTier, shownTier != tier { panels[shownTier]?.orderOut(nil) }
        hideCard()
        let spot = TavernStripGeometry.placement(strip: strip, size: panel.frame.size, canvas: frame.size)
        panel.setFrameOrigin(NSPoint(x: frame.minX + spot.minX, y: frame.maxY - spot.maxY))
        panel.orderFrontRegardless()
        shownTier = tier
        shownSpot = spot
        shownCanvas = frame
        model.openTavernTier = tier
        learnArtPaths()
        if logsTiming {
            panel.displayIfNeeded()
            CATransaction.flush()
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            FileHandle.standardError.write(Data(String(format: "tavern open tier %d: %.1f ms, %d rows\n", tier, ms,
                                                       rows[tier]?.count ?? 0).utf8))
            snapshot(panel, name: "tier-\(tier)")
        }
    }

    /// The first time a list opens in a game: where every pool card's art is, in a few id lookups, so
    /// hovering a card later costs one download.
    private func learnArtPaths() {
        let sheets = model.tavernSheets
        guard artLearnedFor != sheets else { return }
        artLearnedFor = sheets
        var cards: [Int: String] = [:]
        for card in sheets.flatMap({ $0.groups.flatMap(\.cards) }) {
            if let id = card.dbfId { cards[id] = card.name }
        }
        let list = cards.map { (id: $0.key, name: $0.value) }
        Task { [cardArt] in await cardArt.learnArtPaths(list) }
    }

    /// Draws the filter under the strip, with the current choices; rebuilt on every change (it is small).
    func showFilter(canvas frame: CGRect) {
        guard let strip = stripFrame() else { return }
        let scale = TavernStripGeometry.scale(canvas: frame.size)
        let choices = model.tavernFilter.choices(for: model.tavernSheets)
        let width = max(strip.width, (260 * scale).rounded())
        let view = NSHostingView(rootView: TavernFilterView(kinds: choices.kinds, keys: choices.keys, filter: model.tavernFilter,
                                                            scale: scale, width: width) { [weak self] hits in
            self?.filterHits = hits
        })
        let size = view.fittingSize
        let panel = filterPanel ?? makePanel(level: .minionZoom)
        filterPanel = panel
        panel.contentView = view
        panel.setContentSize(size)
        view.layoutSubtreeIfNeeded()
        let spot = TavernStripGeometry.placement(strip: strip, size: size, canvas: frame.size)
        panel.setFrameOrigin(NSPoint(x: frame.minX + spot.minX, y: frame.maxY - spot.maxY))
        panel.orderFrontRegardless()
        filterSpot = spot
        shownCanvas = frame
        if !model.tavernFilterOpen { model.tavernFilterOpen = true }
        if logsTiming { snapshot(panel, name: "filter") }
    }

    /// Demo checks only: a PNG of a panel, drawn by the app itself (no screen recording).
    private func snapshot(_ panel: NSPanel, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["HSBG_TAVERN_SNAPSHOT"], let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
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
        TavernStripGeometry.stripFrame(tiles: model.tavernStripTiles)
    }

    /// What tier `tier`'s panel should show now, or nil when that tier is gone.
    private func wanted(_ tier: Int, canvas: CGSize) -> Built? {
        guard let sheet = model.tavernSheets.first(where: { $0.tier == tier }) else { return nil }
        let filter = model.tavernFilter
        return Built(sheet: filter.apply(to: sheet), size: canvas, summary: filter.isActive ? filter.summary : nil)
    }

    /// Builds stale panels ahead of a click: all of them (a new game), or `atMost` per call (the timer, so a
    /// filter change never stalls the game window).
    private func prepare(atMost limit: Int = .max) {
        guard let frame = canvasFrame(), frame.width > 0 else { return }
        let tiers = Set(model.tavernSheets.map(\.tier))
        for tier in panels.keys where !tiers.contains(tier) {
            if tier == shownTier { hideList() }
            panels[tier]?.orderOut(nil)
            panels[tier] = nil
            built[tier] = nil
            rows[tier] = nil
        }
        let start = DispatchTime.now()
        var count = 0
        for tier in tiers.sorted() where count < limit && built[tier] != wanted(tier, canvas: frame.size) {
            build(tier, canvas: frame)
            count += 1
        }
        if logsTiming, count > 1 {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            FileHandle.standardError.write(Data(String(format: "tavern panels built: %d tiers in %.1f ms\n", count, ms).utf8))
        }
    }

    /// Builds one tier's panel when what it should show changed.
    private func build(_ tier: Int, canvas frame: CGRect) {
        guard let want = wanted(tier, canvas: frame.size), built[tier] != want,
              let strip = stripFrame() ?? expectedStrip(frame.size) else { return }
        let scale = TavernStripGeometry.scale(canvas: frame.size)
        let columnWidth = TavernStripGeometry.columnWidth(canvas: frame.size, scale: scale)
        let maxHeight = TavernStripGeometry.maxListHeight(strip: strip, canvas: frame.size)
        let panel = panels[tier] ?? makePanel(level: .minionZoom)
        let view = NSHostingView(rootView: TavernSheetView(sheet: want.sheet, scale: scale, columnWidth: columnWidth,
                                                            maxHeight: maxHeight, filterSummary: want.summary) { [weak self] hits in
            self?.rows[tier] = hits
        })
        let size = view.fittingSize
        panel.contentView = view
        panel.setContentSize(size)
        view.layoutSubtreeIfNeeded()
        panels[tier] = panel
        built[tier] = want
    }

    /// The strip as it will be drawn, for building the panels before it first appears.
    private func expectedStrip(_ canvas: CGSize) -> CGRect? {
        TavernStripGeometry.stripFrame(tiles: TavernStripGeometry.tiles(tiers: model.tavernSheets.map(\.tier), canvas: canvas))
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
