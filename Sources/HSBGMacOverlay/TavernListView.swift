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

/// Pure geometry of the tier strip and of the list under it, both in the empty space right of the board.
enum TavernStripGeometry {
    static let gap: CGFloat = 8
    static let margin: CGFloat = 8

    /// The list's text scale for a game window: 1 at 1100 points tall.
    static func scale(canvas: CGSize) -> CGFloat {
        min(max(canvas.height / 1100, 0.8), 1.4)
    }

    /// The free space right of the 4:3 board (the curtains of a wide window), left and right edges.
    static func rightSpace(canvas: CGSize) -> ClosedRange<CGFloat> {
        let boardRight = LeaderboardLayout.scaledX(1, width: canvas.width, height: canvas.height)
        let right = canvas.width - margin
        return min(boardRight + margin, right)...right
    }

    /// A row of tiles at the top of the space right of the board, as wide as that space allows. When the
    /// window is too narrow for that, the row hugs the window's right edge.
    static func tiles(tiers: [Int], canvas: CGSize) -> [TavernStripTile] {
        guard !tiers.isEmpty else { return [] }
        let space = rightSpace(canvas: canvas)
        let count = CGFloat(tiers.count)
        let preferred = min(max(canvas.height * 0.045, 22), 52)
        let fitting = (space.upperBound - space.lowerBound) / (count + (count - 1) * 0.15)
        let size = max(min(preferred, fitting), 20).rounded()
        let spacing = (size * 0.15).rounded()
        let width = count * size + (count - 1) * spacing
        let roomy = space.upperBound - space.lowerBound >= width
        let left = (roomy ? space.lowerBound + (space.upperBound - space.lowerBound - width) / 2
                          : canvas.width - margin - width).rounded()
        let top = (canvas.height * 0.025).rounded()
        return tiers.enumerated().map { index, tier in
            TavernStripTile(tier: tier, frame: CGRect(x: left + CGFloat(index) * (size + spacing), y: top,
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

    /// One column of the list: the width of the space right of the board, never narrower than a readable row.
    static func columnWidth(canvas: CGSize, scale: CGFloat) -> CGFloat {
        let space = rightSpace(canvas: canvas)
        return max(space.upperBound - space.lowerBound, 210 * scale).rounded()
    }

    /// How tall the list may be under the strip.
    static func maxListHeight(strip: CGRect, canvas: CGSize) -> CGFloat {
        max(canvas.height - strip.maxY - gap - margin, 200)
    }

    /// The list under the strip, right edges aligned; a list with several columns grows to the left.
    static func placement(strip: CGRect, size: CGSize, canvas: CGSize) -> CGRect {
        let x = max(0, min(strip.maxX, canvas.width) - size.width)
        let y = max(0, min(strip.maxY + gap, canvas.height - size.height))
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

    /// Fills columns top to bottom, group after group, starting a new column when the next group would pass
    /// `maxHeight`. A group is never split, so a tribe stays in one place.
    static func columns<T>(_ items: [T], height: (T) -> CGFloat, spacing: CGFloat, maxHeight: CGFloat) -> [[T]] {
        var result: [[T]] = []
        var current: [T] = []
        var used: CGFloat = 0
        for item in items {
            let needed = height(item) + (current.isEmpty ? 0 : spacing)
            if !current.isEmpty, used + needed > maxHeight {
                result.append(current)
                current = []
                used = 0
            }
            used += height(item) + (current.isEmpty ? 0 : spacing)
            current.append(item)
        }
        if !current.isEmpty { result.append(current) }
        return result
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

/// Everything one tier offers in this lobby, as a narrow list: tribe sections, then amalgams, no tribe and
/// spells, wrapping into another column (to the left) when the window is not tall enough.
struct TavernSheetView: View {
    let sheet: TavernSheet
    let scale: CGFloat
    let columnWidth: CGFloat
    let maxHeight: CGFloat
    /// Where each card's row ended up, for hovering a row.
    var onRows: ([TavernRowHit]) -> Void = { _ in }

    var rowHeight: CGFloat { (18 * scale).rounded() }
    var headerHeight: CGFloat { (21 * scale).rounded() }
    private var spacing: CGFloat { (6 * scale).rounded() }
    /// Title, footer lines and padding, so the columns get the rest.
    private var chrome: CGFloat { 110 * scale }

    private var columns: [[TavernGroup]] {
        TavernStripGeometry.columns(sheet.groups, height: { headerHeight + CGFloat($0.cards.count) * rowHeight },
                                    spacing: spacing, maxHeight: max(maxHeight - chrome, rowHeight * 6))
    }

    var body: some View {
        let columns = self.columns
        let width = CGFloat(max(columns.count, 1)) * columnWidth + CGFloat(max(columns.count - 1, 0)) * spacing
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                Text(verbatim: "Tier \(sheet.tier)")
                    .font(.system(size: 14 * scale, weight: .bold))
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
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(column) { group in
                            TavernSection(group: group, scale: scale, rowHeight: rowHeight, headerHeight: headerHeight)
                        }
                    }
                    .frame(width: columnWidth, alignment: .leading)
                }
            }
            if !sheet.missingTribes.isEmpty {
                (Text("Not in this lobby: ").bold()
                    + Text(verbatim: sheet.missingTribes.map(TribeNames.plural).joined(separator: ", ")))
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(EdgeInkPalette.dim)
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: PoolMechanic.allCases.map { "\($0.tag) \($0.label)" }.joined(separator: " · "))
                .font(.system(size: 9 * scale))
                .foregroundStyle(EdgeInkPalette.dim.opacity(0.8))
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8 * scale)
        .background(EdgeInkPalette.cardBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .fixedSize()
        .coordinateSpace(name: TavernRow.space)
        .onPreferenceChange(TavernRowKey.self) { onRows($0) }
    }
}

/// One tribe (or amalgams, no tribe, spells): a tinted header bar, then one row per card.
private struct TavernSection: View {
    let group: TavernGroup
    let scale: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat

    private var tint: Color { group.tribe.map { TribeStyle.style(for: $0).color } ?? EdgeInkPalette.gold }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5 * scale) {
                if let tribe = group.tribe {
                    TribeIcon(tribe: tribe, size: 14 * scale)
                }
                Text(verbatim: group.title)
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 2)
                Text(verbatim: "\(group.cards.count)")
                    .font(.system(size: 10 * scale, weight: .semibold).monospacedDigit())
                    .foregroundStyle(EdgeInkPalette.dim)
            }
            .padding(.horizontal, 5 * scale)
            .frame(height: headerHeight)
            .background(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.06)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 4 * scale))
            ForEach(group.cards, id: \.id) { card in
                TavernRow(card: card, scale: scale, tint: tint)
                    .frame(height: rowHeight)
            }
        }
    }
}

private struct TavernRow: View {
    static let space = "tavernSheet"
    let card: PoolCard
    let scale: CGFloat
    let tint: Color

    var body: some View {
        HStack(spacing: 3 * scale) {
            // A thin bar in the section's colour keeps long columns readable at a glance.
            RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.55)).frame(width: 2 * scale)
                .padding(.vertical, 3 * scale)
            Text(verbatim: card.name)
                .font(.system(size: 11.5 * scale, weight: .medium))
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
            if card.isSpell, let cost = card.cost {
                Text(verbatim: "\(cost)")
                    .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: 14 * scale, height: 14 * scale)
                    .background(EdgeInkPalette.leaderGold, in: Circle())
                    .accessibilityLabel("\(cost) gold")
            } else if let attack = card.attack, let health = card.health {
                Text(verbatim: "\(attack)/\(health)")
                    .font(.system(size: 9.5 * scale).monospacedDigit())
                    .foregroundStyle(EdgeInkPalette.dim)
                    .fixedSize()
            }
        }
        .padding(.leading, 2 * scale)
        .padding(.trailing, 4 * scale)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: TavernRowKey.self,
                                   value: [TavernRowHit(card: card, frame: geometry.frame(in: .named(Self.space)))])
        })
    }
}
