import AppKit
import Combine
import SwiftUI

/// One tier button of the strip, in game-window coordinates (top-left origin).
struct TavernStripTile: Equatable {
    var tier: Int
    var frame: CGRect
}

struct TavernStripKey: PreferenceKey {
    static let defaultValue: [TavernStripTile] = []
    static func reduce(value: inout [TavernStripTile], nextValue: () -> [TavernStripTile]) {
        value += nextValue()
    }
}

/// Pure geometry of the tier strip and of the list under it.
enum TavernStripGeometry {
    /// The list's text scale for a game window: 1 at 1100 points tall.
    static func scale(canvas: CGSize) -> CGFloat {
        min(max(canvas.height / 1100, 0.8), 1.4)
    }

    static func tileSize(canvas: CGSize) -> CGFloat {
        min(max(canvas.height * 0.03, 18), 40)
    }

    /// A row of tiles centred at the top of the game window, just under its edge.
    static func tiles(tiers: [Int], canvas: CGSize) -> [TavernStripTile] {
        let size = tileSize(canvas: canvas)
        let spacing = (size * 0.18).rounded()
        let width = CGFloat(tiers.count) * size + CGFloat(max(tiers.count - 1, 0)) * spacing
        let left = ((canvas.width - width) / 2).rounded()
        let top = (canvas.height * 0.006).rounded()
        return tiers.enumerated().map { index, tier in
            TavernStripTile(tier: tier, frame: CGRect(x: left + CGFloat(index) * (size + spacing), y: top,
                                                      width: size, height: size))
        }
    }

    static func hitTier(at point: CGPoint, in tiles: [TavernStripTile]) -> Int? {
        tiles.first { $0.frame.contains(point) }?.tier
    }

    /// The list under the strip, centred on it and kept inside the game window.
    static func placement(strip: CGRect, size: CGSize, canvas: CGSize) -> CGRect {
        let x = max(0, min(strip.midX - size.width / 2, canvas.width - size.width))
        let y = min(strip.maxY + 6, max(0, canvas.height - size.height))
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// Splits columns into rows that fit `maxWidth`.
    static func rows<T>(_ columns: [T], columnWidth: CGFloat, spacing: CGFloat, maxWidth: CGFloat) -> [[T]] {
        let perRow = max(1, Int((maxWidth + spacing) / (columnWidth + spacing)))
        return stride(from: 0, to: columns.count, by: perRow).map { Array(columns[$0..<min($0 + perRow, columns.count)]) }
    }
}

/// The slim tier strip drawn in the shop. Click-through like the rest of the overlay; hover is watched by
/// `TavernListController`.
struct TavernStrip: View {
    let tiers: [Int]
    let canvas: CGSize

    var body: some View {
        let tiles = TavernStripGeometry.tiles(tiers: tiers, canvas: canvas)
        ZStack(alignment: .topLeading) {
            ForEach(tiles, id: \.tier) { tile in
                Text(verbatim: "\(tile.tier)")
                    .font(.system(size: tile.frame.height * 0.58, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: tile.frame.width, height: tile.frame.height)
                    .background(TierBadge.color(for: tile.tier).opacity(0.9), in: RoundedRectangle(cornerRadius: tile.frame.height * 0.22))
                    .overlay(RoundedRectangle(cornerRadius: tile.frame.height * 0.22).strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
                    .offset(x: tile.frame.minX, y: tile.frame.minY)
                    .accessibilityLabel("Tavern tier \(tile.tier)")
            }
        }
        .preference(key: TavernStripKey.self, value: tiles)
    }
}

/// Everything one tier offers in this lobby: a column per tribe, then amalgams, no tribe and spells.
struct TavernSheetView: View {
    let sheet: TavernSheet
    let scale: CGFloat
    let maxWidth: CGFloat

    private var columnWidth: CGFloat { 158 * scale }
    private var spacing: CGFloat { 10 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(spacing: 6 * scale) {
                Text(verbatim: "Tier \(sheet.tier)")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(TierBadge.color(for: sheet.tier))
                Text(verbatim: "\(sheet.minionCount) minions")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(EdgeInkPalette.dim)
            }
            if sheet.groups.isEmpty {
                Text("Nothing on this tier in this lobby")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(EdgeInkPalette.dim)
            }
            ForEach(Array(TavernStripGeometry.rows(sheet.groups, columnWidth: columnWidth, spacing: spacing,
                                                   maxWidth: maxWidth - 20 * scale).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row) { group in
                        TavernColumn(group: group, scale: scale).frame(width: columnWidth, alignment: .leading)
                    }
                }
            }
            Text(verbatim: PoolMechanic.allCases.map { "\($0.tag) \($0.label)" }.joined(separator: " · "))
                .font(.system(size: 9.5 * scale))
                .foregroundStyle(EdgeInkPalette.dim)
        }
        .padding(10 * scale)
        .background(EdgeInkPalette.cardBackground.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .fixedSize()
    }
}

private struct TavernColumn: View {
    let group: TavernGroup
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            HStack(spacing: 4 * scale) {
                if let tribe = group.tribe {
                    TribeIcon(tribe: tribe, size: 13 * scale)
                }
                Text(verbatim: group.title)
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .foregroundStyle(group.tribe.map { TribeStyle.style(for: $0).color } ?? EdgeInkPalette.gold)
                Text(verbatim: "\(group.cards.count)")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(EdgeInkPalette.dim)
            }
            .padding(.bottom, 1 * scale)
            ForEach(group.cards, id: \.id) { card in
                TavernRow(card: card, scale: scale)
            }
        }
    }
}

private struct TavernRow: View {
    let card: PoolCard
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 3 * scale) {
            Text(verbatim: card.name)
                .font(.system(size: 11 * scale))
                .foregroundStyle(EdgeInkPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            ForEach(card.shownMechanics, id: \.self) { mechanic in
                Text(verbatim: mechanic.tag)
                    .font(.system(size: 8.5 * scale, weight: .bold))
                    .foregroundStyle(EdgeInkPalette.gold)
                    .padding(.horizontal, 2.5 * scale)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
            }
            Spacer(minLength: 2 * scale)
            Text(verbatim: stats)
                .font(.system(size: 9.5 * scale).monospacedDigit())
                .foregroundStyle(EdgeInkPalette.dim)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private var stats: String {
        if card.isSpell { return card.cost.map { "\($0)g" } ?? "" }
        guard let attack = card.attack, let health = card.health else { return "" }
        return "\(attack)/\(health)"
    }
}

/// Shows a tier's list while the mouse is over its tile in the strip. The panels for every tier are built
/// once per game (and when the window size changes), so hovering only orders one in and the others out.
/// Like the minion zoom, it watches mouse moves only (no extra permission) and the panels ignore the mouse.
@MainActor
final class TavernListController {
    private let model: OverlayModel
    private let canvasFrame: () -> CGRect?
    private var monitors: [Any] = []
    private var panels: [Int: NSPanel] = [:]
    private var builtFor: (sheets: [TavernSheet], size: CGSize)?
    private var shownTier: Int?
    private var sheetsWatch: AnyCancellable?
    /// `HSBG_TAVERN_TIMING=1` prints hover-to-paint times to stderr (tiers and milliseconds only).
    private let logsTiming = ProcessInfo.processInfo.environment["HSBG_TAVERN_TIMING"] == "1"

    init(model: OverlayModel, canvasFrame: @escaping () -> CGRect?) {
        self.model = model
        self.canvasFrame = canvasFrame
    }

    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
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

    /// On the position timer: hides the list when the strip went away, and keeps the panels built.
    func refresh() {
        prepare()
        if shownTier != nil { mouseMoved() }
    }

    func hide() {
        if let shownTier { panels[shownTier]?.orderOut(nil) }
        shownTier = nil
    }

    private func mouseMoved() {
        guard model.showsTavernStrip, let frame = canvasFrame() else {
            if shownTier != nil { hide() }
            return
        }
        let point = MinionZoomGeometry.canvasPoint(fromScreen: NSEvent.mouseLocation, canvasCocoaFrame: frame)
        let tier = TavernStripGeometry.hitTier(at: point, in: model.tavernStripTiles)
        guard tier != shownTier else { return }
        if let tier { show(tier, canvas: frame) } else { hide() }
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
        if logsTiming {
            panel.displayIfNeeded()
            CATransaction.flush()
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            FileHandle.standardError.write(Data(String(format: "tavern hover tier %d: %.1f ms\n", tier, ms).utf8))
            // Demo checks only: a PNG of the panel, drawn by the app itself (no screen recording).
            if let directory = ProcessInfo.processInfo.environment["HSBG_TAVERN_SNAPSHOT"], let view = panel.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("tier-\(tier).png"))
            }
        }
    }

    private func stripFrame() -> CGRect? {
        let frames = model.tavernStripTiles.map(\.frame)
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Builds one hidden panel per tier when the sheets or the window size changed.
    private func prepare() {
        let sheets = model.tavernSheets
        guard let frame = canvasFrame(), frame.width > 0 else { return }
        if let builtFor, builtFor.sheets == sheets, builtFor.size == frame.size { return }
        let start = DispatchTime.now()
        hide()
        panels.values.forEach { $0.orderOut(nil) }
        let scale = TavernStripGeometry.scale(canvas: frame.size)
        var built: [Int: NSPanel] = [:]
        for sheet in sheets {
            let panel = panels[sheet.tier] ?? makePanel()
            let view = NSHostingView(rootView: TavernSheetView(sheet: sheet, scale: scale, maxWidth: frame.width * 0.94))
            let size = view.fittingSize
            panel.contentView = view
            panel.setContentSize(size)
            built[sheet.tier] = panel
        }
        panels = built
        builtFor = (sheets, frame.size)
        if logsTiming, !sheets.isEmpty {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            FileHandle.standardError.write(Data(String(format: "tavern panels built: %d tiers in %.1f ms\n", sheets.count, ms).utf8))
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .minionZoom
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        return panel
    }
}
