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

/// Where one card's row is inside a tier's list (the list's own coordinates, top-left origin).
struct TavernRowHit: Equatable {
    var card: PoolCard
    var frame: CGRect
}

struct TavernRowKey: PreferenceKey {
    static let defaultValue: [TavernRowHit] = []
    static func reduce(value: inout [TavernRowHit], nextValue: () -> [TavernRowHit]) {
        value += nextValue()
    }
}

extension NSWindow.Level {
    /// The enlarged card over the tavern list.
    static let tavernCardZoom = NSWindow.Level(rawValue: NSWindow.Level.minionZoom.rawValue + 1)
}

/// Pure geometry of the tier strip and of the list beside it.
enum TavernStripGeometry {
    static let gap: CGFloat = 8

    /// The list's text scale for a game window: 1 at 1100 points tall.
    static func scale(canvas: CGSize) -> CGFloat {
        min(max(canvas.height / 1100, 0.8), 1.4)
    }

    static func tileSize(canvas: CGSize) -> CGFloat {
        min(max(canvas.height * 0.042, 22), 48)
    }

    /// A column of tiles in the empty space right of the board (the curtains of a wide window), centred
    /// on the window's height. When the window is too narrow for that, they hug its right edge.
    static func tiles(tiers: [Int], canvas: CGSize) -> [TavernStripTile] {
        let size = tileSize(canvas: canvas)
        let spacing = (size * 0.2).rounded()
        let boardRight = LeaderboardLayout.scaledX(1, width: canvas.width, height: canvas.height)
        let left = min(boardRight + size * 0.5, canvas.width - size - 4).rounded()
        let height = CGFloat(tiers.count) * size + CGFloat(max(tiers.count - 1, 0)) * spacing
        let top = max(0, (canvas.height - height) / 2).rounded()
        return tiers.enumerated().map { index, tier in
            TavernStripTile(tier: tier, frame: CGRect(x: left, y: top + CGFloat(index) * (size + spacing),
                                                      width: size, height: size))
        }
    }

    /// A tier you cannot buy from yet.
    static func isAhead(_ tier: Int, of current: Int?) -> Bool {
        guard let current, current > 0 else { return false }
        return tier > current
    }

    static func hitTier(at point: CGPoint, in tiles: [TavernStripTile]) -> Int? {
        tiles.first { $0.frame.contains(point) }?.tier
    }

    /// How wide a list can be: everything left of the strip, so it never covers it.
    static func maxListWidth(strip: CGRect) -> CGFloat {
        max(strip.minX - gap * 2, 200)
    }

    /// The list left of the strip, centred on the hovered tile's height and kept inside the game window.
    static func placement(strip: CGRect, tile: CGRect, size: CGSize, canvas: CGSize) -> CGRect {
        let x = max(0, strip.minX - gap - size.width)
        let y = max(0, min(tile.midY - size.height / 2, canvas.height - size.height))
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// The enlarged card: left of the list when there is room, else beside the row itself; centred on the row.
    static func cardPlacement(row: CGRect, list: CGRect, size: CGSize, canvas: CGSize) -> CGRect {
        let x: CGFloat
        if list.minX >= size.width + gap {
            x = list.minX - gap - size.width
        } else if row.maxX + gap + size.width <= canvas.width {
            x = row.maxX + gap
        } else {
            x = max(0, row.minX - gap - size.width)
        }
        let y = max(0, min(row.midY - size.height / 2, canvas.height - size.height))
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
    /// Your own tavern tier: ringed; the tiers above it are dimmed (still hoverable, to plan ahead).
    var currentTier: Int?
    /// The game's tier shields (from HSTracker) instead of numbers, as on the leaderboard.
    var showsIcons = true

    var body: some View {
        let tiles = TavernStripGeometry.tiles(tiers: tiers, canvas: canvas)
        ZStack(alignment: .topLeading) {
            ForEach(tiles, id: \.tier) { tile in
                let isCurrent = tile.tier == currentTier
                Group {
                    if showsIcons, let icon = TierIcons.image(for: tile.tier) {
                        // The game's own shield; yours glows white.
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: tile.frame.width, height: tile.frame.height)
                            .shadow(color: isCurrent ? .white : .black.opacity(0.6), radius: isCurrent ? tile.frame.height * 0.12 : 2)
                    } else {
                        Text(verbatim: "\(tile.tier)")
                            .font(.system(size: tile.frame.height * 0.58, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black.opacity(0.85))
                            .frame(width: tile.frame.width, height: tile.frame.height)
                            .background(TierBadge.color(for: tile.tier).opacity(0.9), in: RoundedRectangle(cornerRadius: tile.frame.height * 0.22))
                            .overlay(RoundedRectangle(cornerRadius: tile.frame.height * 0.22)
                                .strokeBorder(isCurrent ? Color.white : Color.black.opacity(0.55),
                                              lineWidth: isCurrent ? max(2, tile.frame.height * 0.07) : 1))
                    }
                }
                    .opacity(TavernStripGeometry.isAhead(tile.tier, of: currentTier) ? 0.45 : 1)
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
    /// Where each card's row ended up, for hovering a row.
    var onRows: ([TavernRowHit]) -> Void = { _ in }

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
        .coordinateSpace(name: TavernRow.space)
        .onPreferenceChange(TavernRowKey.self) { onRows($0) }
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
    static let space = "tavernSheet"
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
        .background(GeometryReader { geometry in
            Color.clear.preference(key: TavernRowKey.self,
                                   value: [TavernRowHit(card: card, frame: geometry.frame(in: .named(Self.space)))])
        })
    }

    private var stats: String {
        if card.isSpell { return card.cost.map { "\($0)g" } ?? "" }
        guard let attack = card.attack, let health = card.health else { return "" }
        return "\(attack)/\(health)"
    }
}

