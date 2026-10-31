import CoreGraphics
import Foundation
import SwiftUI

/// Which player the NEXT OPPONENT card is about, if any. One card at a time, recruit
/// phase only: hidden in combat (even when labels stay visible there), after the game
/// is over (the log keeps the last next-opponent tag after the final combat) and when
/// the game names nobody.
enum NextOpponentRules {
    static func opponent(players: [BattlegroundsPlayer], nextPlace: Int, isBattlegrounds: Bool,
                         isInCombat: Bool, isGameOver: Bool) -> BattlegroundsPlayer? {
        guard isBattlegrounds, !isInCombat, !isGameOver, nextPlace > 0 else { return nil }
        let matches = players.filter { $0.placement == nextPlace && !$0.isLocalPlayer && !$0.name.isEmpty }
        // Two players claiming one place means the lobby is still settling.
        return matches.count == 1 ? matches[0] : nil
    }
}

enum TribeNames {
    private static let plural = [
        "BEAST": "Beasts", "DEMON": "Demons", "DRAGON": "Dragons", "ELEMENTAL": "Elementals",
        "MECHANICAL": "Mechs", "MURLOC": "Murlocs", "NAGA": "Nagas", "PIRATE": "Pirates",
        "QUILBOAR": "Quilboars", "UNDEAD": "Undead", "ABERRATION": "Aberrations", "ALL": "Amalgams",
    ]

    static func plural(_ key: String) -> String {
        plural[key] ?? key.capitalized
    }
}

/// The text of the card, ready to draw. Anything unknown is a dash, never a made-up number.
struct NextOpponentContent: Equatable {
    static let dash = "—"

    var name: String
    var initial: String
    var mmr: String
    /// "#2 of 5 listed"; nil when the player is not listed.
    var rank: String?
    var record: String
    var streak: StreakRun?
    /// Tier for the shield, nil when unknown; `tierTurn` is the turn it was reached (tier 2+ only).
    var tier: Int?
    var tierTurn: Int?
    /// "T5 on turn 8".
    var tierPace: String
    /// "Dragons ×5 · 7 minions · T5": one line.
    var lastBoard: String
    var isLastBoardStale: Bool
    var triples: String

    init(player: BattlegroundsPlayer, lobby: [BattlegroundsPlayer], currentTurn: Int) {
        let dash = Self.dash
        name = player.name.split(separator: "#").first.map(String.init) ?? player.name
        initial = name.first.map { String($0).uppercased() } ?? "?"
        mmr = player.rating.map(RatingFormat.text) ?? dash
        rank = LobbyStats.rank(of: player, in: lobby).map { "#\($0.rank) of \($0.listed) listed" }
        record = player.wins + player.losses > 0 ? "\(player.wins)–\(player.losses)" : dash
        if player.winStreak >= 2 {
            streak = StreakRun(isLoss: false, count: player.winStreak)
        } else if player.lossStreak >= 2 {
            streak = StreakRun(isLoss: true, count: player.lossStreak)
        }
        tier = player.tavernTier.flatMap { $0 > 0 ? $0 : nil }
        tierTurn = (player.tavernTier ?? 0) >= 2 ? player.tierReachedTurn : nil
        switch (player.tavernTier, player.tierReachedTurn) {
        case let (tier?, turn?) where tier >= 2: tierPace = "T\(tier) on turn \(turn)"
        case let (tier?, _): tierPace = "T\(tier)"
        default: tierPace = dash
        }
        if let main = player.lastSeenTribes.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).first {
            var parts = ["\(TribeNames.plural(main.key)) ×\(main.value)"]
            if let size = player.lastBoardSize { parts.append(size == 1 ? "1 minion" : "\(size) minions") }
            if let tier = player.lastBoardTier { parts.append("T\(tier)") }
            lastBoard = parts.joined(separator: " · ")
        } else {
            lastBoard = dash
        }
        isLastBoardStale = player.lastSeenTurn.map { currentTurn - $0 > 2 } ?? false
        triples = player.triples.map(String.init) ?? dash
    }
}

/// Geometry of the card: width, scale, which rows fit, and where it docks.
struct NextOpponentLayout: Equatable {
    /// Rows from most to least important; the last ones go first on small windows.
    struct Rows: Equatable {
        var showsTierPace: Bool
        var showsTriples: Bool
    }

    /// Design size: everything below is drawn at this width and multiplied by `scale`.
    static let designWidth: CGFloat = 270
    static let scaleRange: ClosedRange<CGFloat> = 0.6...1.3
    static let tierPaceMinimumScale: CGFloat = 0.65
    static let triplesMinimumScale: CGFloat = 0.75
    /// Without HSTracker's window to match, the card is this fraction of the game's height wide.
    static let fallbackWidthRatio: CGFloat = 0.22
    static let fallbackLeftMargin: CGFloat = 0.01
    static let fallbackTop: CGFloat = 0.52
    static let dockGapRatio: CGFloat = 0.012
    static let edgeMargin: CGFloat = 0.01

    /// Heights at design size.
    static let paddingHeight: CGFloat = 14
    static let overlineHeight: CGFloat = 14
    static let headerHeight: CGFloat = 40
    static let rowHeight: CGFloat = 46
    static let spacing: CGFloat = 8

    let canvas: CGSize
    /// HSTracker's left panel in canvas coordinates (top-left origin), when found.
    let trackerPanel: CGRect?

    var width: CGFloat {
        let ideal = trackerPanel?.width ?? canvas.height * Self.fallbackWidthRatio
        // Never wider than a third of the window, whatever HSTracker's window turns out to be.
        return min(max(ideal, canvas.height * 0.14), min(canvas.height * 0.32, canvas.width / 3))
    }

    var scale: CGFloat {
        min(max(width / Self.designWidth, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    var rows: Rows {
        Rows(showsTierPace: scale >= Self.tierPaceMinimumScale, showsTriples: scale >= Self.triplesMinimumScale)
    }

    /// Height at design size for the visible rows: header, record (+ tier pace), board, triples.
    var height: CGFloat {
        let rows = rows
        let blocks = 2 + (rows.showsTriples ? 1 : 0)
        let divider: CGFloat = 1
        let content = Self.overlineHeight + Self.headerHeight + divider + CGFloat(blocks) * Self.rowHeight
        let gaps = CGFloat(blocks + 2) * Self.spacing
        return (content + gaps + 2 * Self.paddingHeight) * scale
    }

    var size: CGSize { CGSize(width: width, height: height) }

    /// Top-left of the card: under HSTracker's panel, left-aligned with it, kept inside the
    /// game window. With no panel: 1 % from the left edge, 52 % down.
    var origin: CGPoint {
        let margin = canvas.width * Self.edgeMargin
        var x: CGFloat
        var y: CGFloat
        if let panel = trackerPanel {
            x = panel.minX
            y = panel.maxY + canvas.height * Self.dockGapRatio
        } else {
            x = canvas.width * Self.fallbackLeftMargin
            y = canvas.height * Self.fallbackTop
        }
        x = max(margin, min(x, canvas.width - width - margin))
        y = max(margin, min(y, canvas.height - height - canvas.height * Self.edgeMargin))
        return CGPoint(x: x, y: y)
    }
}

/// Picks HSTracker's left-hand panel among the frames of its windows, all in the
/// game window's coordinates (top-left origin).
enum TrackerPanelPicker {
    static func leftPanel(among frames: [CGRect], canvas: CGSize) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: canvas)
        let candidates = frames.filter { frame in
            let clipped = frame.intersection(bounds)
            return !clipped.isNull
                && clipped.height >= canvas.height * 0.05
                && clipped.width >= canvas.width * 0.05
                // A panel, not a window covering the game; docked on the left side.
                && frame.width <= canvas.width * 0.35
                && frame.minX < canvas.width * 0.35
        }
        guard let panel = candidates.max(by: { $0.maxY < $1.maxY }) else { return nil }
        return panel.intersection(bounds)
    }
}

struct NextOpponentCard: View {
    let content: NextOpponentContent
    let layout: NextOpponentLayout

    var body: some View {
        let s = layout.scale
        let rows = layout.rows
        VStack(alignment: .leading, spacing: NextOpponentLayout.spacing) {
            label("NEXT OPPONENT")
                .frame(height: NextOpponentLayout.overlineHeight, alignment: .leading)
            header
                .frame(height: NextOpponentLayout.headerHeight)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                block("RECORD") {
                    HStack(spacing: 6) {
                        Text(verbatim: content.record).font(number).foregroundStyle(EdgeInkPalette.ink)
                        if let streak = content.streak {
                            StreakMark(isLoss: streak.isLoss, count: streak.count, arrowSize: 11, gap: 2)
                                .font(secondary)
                            Text(verbatim: streak.isLoss ? "lost" : "not lost")
                                .font(secondary).foregroundStyle(EdgeInkPalette.dim)
                        }
                    }
                }
                if rows.showsTierPace {
                    block("TIER PACE") {
                        if content.tier != nil {
                            HStack(spacing: 6) {
                                TierShield(tier: content.tier, height: 28)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: "T\(content.tier ?? 0)").font(number).foregroundStyle(EdgeInkPalette.ink)
                                    if let turn = content.tierTurn {
                                        Text(verbatim: "on turn \(turn)").font(secondary).foregroundStyle(EdgeInkPalette.dim)
                                    }
                                }
                                .lineLimit(1)
                            }
                        } else {
                            Text(verbatim: content.tierPace).font(number).foregroundStyle(EdgeInkPalette.ink)
                        }
                    }
                }
            }
            .frame(height: NextOpponentLayout.rowHeight, alignment: .top)
            block("LAST BOARD") {
                Text(verbatim: content.lastBoard)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EdgeInkPalette.ink)
                    .opacity(content.isLastBoardStale ? 0.55 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(height: NextOpponentLayout.rowHeight, alignment: .top)
            if rows.showsTriples {
                block("TRIPLES") {
                    Text(verbatim: content.triples).font(number).foregroundStyle(EdgeInkPalette.ink)
                }
                .frame(height: NextOpponentLayout.rowHeight, alignment: .top)
            }
        }
        .padding(NextOpponentLayout.paddingHeight)
        .frame(width: NextOpponentLayout.designWidth, alignment: .leading)
        .background(EdgeInkPalette.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            UnevenRule().fill(EdgeInkPalette.gold).frame(width: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        .scaleEffect(s, anchor: .topLeading)
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var number: Font { .system(size: 17, weight: .semibold, design: .rounded).monospacedDigit() }
    private var secondary: Font { .system(size: 10.5, weight: .medium) }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(EdgeInkPalette.dim)
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            body()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Initial in a ring (the hero art belongs to the game, so it is not copied), then name, MMR and rank.
    private var header: some View {
        HStack(spacing: 10) {
            Text(verbatim: content.initial)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(EdgeInkPalette.gold)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(EdgeInkPalette.gold, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: content.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(EdgeInkPalette.ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
                HStack(spacing: 6) {
                    Text(verbatim: content.mmr)
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(content.mmr == NextOpponentContent.dash ? EdgeInkPalette.dim : EdgeInkPalette.gold)
                    if let rank = content.rank {
                        Text(verbatim: rank).font(secondary).foregroundStyle(EdgeInkPalette.dim)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The gold rule on the card's left edge, following the corner radius.
private struct UnevenRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 1)
    }
}
