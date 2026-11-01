import CoreGraphics
import Foundation
import SwiftUI

/// Which player the NEXT OPPONENT card is about, if any. One card at a time, recruit
/// phase only: hidden in combat (unless the player turned the option on), after the game
/// is over (the log keeps the last next-opponent tag after the final combat) and when
/// the game names nobody.
enum NextOpponentRules {
    static func opponent(players: [BattlegroundsPlayer], nextPlace: Int, isBattlegrounds: Bool,
                         isInCombat: Bool, isGameOver: Bool, showsInCombat: Bool = false) -> BattlegroundsPlayer? {
        guard isBattlegrounds, showsInCombat || !isInCombat, !isGameOver, nextPlace > 0 else { return nil }
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
    static let notFought = "Not fought yet"

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
    /// False before you have fought them: the card says so in one line.
    var hasLastBoard: Bool
    /// Nil at zero: the card shows no triples then.
    var triples: String?
    /// Current health (maximum minus damage) and armor, kept apart; nil when not known.
    var health: Int?
    var armor: Int?
    /// Points they lost in their last combat ("down 9"); nil when unknown or when they were not hurt.
    var lastCombatDamage: Int?
    /// Rating change since the baseline list; nil without one (or for unlisted players).
    var mmrChange: RatingChange?
    /// Their latest decisive fights with you, if any.
    var beatYou: FightWithYou?
    var youBeatThem: FightWithYou?
    var hasFightWithYou: Bool { beatYou != nil || youBeatThem != nil }
    /// Whether the third row (health, triples) has anything to show.
    var hasStatusRow: Bool { health != nil || triples != nil }

    init(player: BattlegroundsPlayer, lobby: [BattlegroundsPlayer], currentTurn: Int,
         baseline: RatingBaseline? = nil, now: Date = Date()) {
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
            lastBoard = Self.notFought
        }
        hasLastBoard = !player.lastSeenTribes.isEmpty
        isLastBoardStale = player.lastSeenTurn.map { currentTurn - $0 > 2 } ?? false
        triples = (player.triples ?? 0) > 0 ? player.triples.map(String.init) : nil
        health = player.currentHealth
        armor = player.armor > 0 ? player.armor : nil
        lastCombatDamage = (player.lastCombatDamage ?? 0) > 0 ? player.lastCombatDamage : nil
        mmrChange = RatingChange.make(current: player.rating, name: player.name, baseline: baseline, now: now)
        beatYou = player.fightsWithYou.last { !$0.youWon }
        youBeatThem = player.fightsWithYou.last { $0.youWon }
    }
}

/// Geometry of the card: width, scale, which rows fit, and where it docks.
struct NextOpponentLayout: Equatable {
    /// Rows from most to least important; the last ones go first on small windows.
    struct Rows: Equatable {
        var showsTierPace: Bool
        /// Health and triples, side by side.
        var showsStatus: Bool
        var showsVersus = false
    }

    /// Design size: everything below is drawn at this width and multiplied by `scale`.
    static let designWidth: CGFloat = 270
    static let scaleRange: ClosedRange<CGFloat> = 0.6...1.3
    static let tierPaceMinimumScale: CGFloat = 0.65
    static let statusMinimumScale: CGFloat = 0.75
    static let versusMinimumScale: CGFloat = 0.7
    /// Without HSTracker's window to match, the card is this fraction of the game's height wide.
    static let fallbackWidthRatio: CGFloat = 0.22
    static let fallbackLeftMargin: CGFloat = 0.01
    /// Without a measurable panel the card sits on the bottom of the window (8 % margin for the
    /// player's own name), growing upward; it may not rise above `fallbackTop`, which is below
    /// a "Latest Games" list of 10 rows.
    static let fallbackTop: CGFloat = 0.62
    static let fallbackBottomMargin: CGFloat = 0.08
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
    /// The card must end left of this x (where the leaderboard labels start); nil for no limit.
    var rightLimit: CGFloat?
    /// What the card has to show, since empty rows are left out.
    var hasStatusRow = true
    var hasVersusRow = false

    private var left: CGFloat { trackerPanel?.minX ?? canvas.width * Self.fallbackLeftMargin }

    private var maxWidth: CGFloat {
        guard let rightLimit else { return .infinity }
        return max(rightLimit - max(left, canvas.width * Self.edgeMargin), 0)
    }

    /// HSTracker usually draws its panel inside one big transparent window, so its real bottom
    /// cannot be measured from window bounds. Without a separate panel window the card starts
    /// here (60 %): below a "Latest Games" list of up to about 8 rows.
    private var wantedTop: CGFloat {
        trackerPanel.map { $0.maxY + canvas.height * Self.dockGapRatio } ?? canvas.height * Self.fallbackTop
    }

    /// Lowest y the card may reach.
    private var bottomLimit: CGFloat {
        canvas.height * (1 - (trackerPanel == nil ? Self.fallbackBottomMargin : Self.edgeMargin))
    }

    private var idealWidth: CGFloat {
        let ideal = trackerPanel?.width ?? canvas.height * Self.fallbackWidthRatio
        // Never wider than a third of the window, whatever HSTracker's window turns out to be.
        return min(max(ideal, canvas.height * 0.14), min(canvas.height * 0.32, canvas.width / 3))
    }

    private var idealScale: CGFloat {
        min(max(idealWidth / Self.designWidth, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    static func rows(at scale: CGFloat, hasStatus: Bool = true, hasVersus: Bool = false) -> Rows {
        Rows(showsTierPace: scale >= tierPaceMinimumScale,
             showsStatus: hasStatus && scale >= statusMinimumScale,
             showsVersus: hasVersus && scale >= versusMinimumScale)
    }

    /// Height at design size (scale 1) for the rows shown at `scale`.
    static func designHeight(rows: Rows) -> CGFloat {
        let blocks = 2 + (rows.showsStatus ? 1 : 0) + (rows.showsVersus ? 1 : 0)
        let divider: CGFloat = 1
        let content = overlineHeight + headerHeight + divider + CGFloat(blocks) * rowHeight
        let gaps = CGFloat(blocks + 2) * spacing
        return content + gaps + 2 * paddingHeight
    }

    /// The scale actually used: the one the width asks for, shrunk (down to the minimum) when the
    /// card would not fit between its top and the bottom of the window, so it never has to move
    /// up over HSTracker's panel.
    var scale: CGFloat {
        let available = bottomLimit - wantedTop
        // Narrow the card first when it would run into the leaderboard.
        var scale = min(idealScale, idealScale * maxWidth / idealWidth)
        scale = max(scale, Self.scaleRange.lowerBound)
        for _ in 0..<4 {
            let height = Self.designHeight(rows: Self.rows(at: scale, hasStatus: hasStatusRow, hasVersus: hasVersusRow)) * scale
            if height <= available { return scale }
            let fitted = max(available / Self.designHeight(rows: Self.rows(at: scale, hasStatus: hasStatusRow, hasVersus: hasVersusRow)), Self.scaleRange.lowerBound)
            if fitted >= scale { break }
            scale = fitted
        }
        return scale
    }

    /// False when even the smallest card would run past the bottom of the window: the card is
    /// then hidden rather than drawn over HSTracker's panel.
    var fits: Bool {
        Self.designHeight(rows: Self.rows(at: scale, hasStatus: hasStatusRow, hasVersus: hasVersusRow)) * scale <= bottomLimit - wantedTop + 0.001
            && width <= maxWidth + 0.001
    }

    var rows: Rows { Self.rows(at: scale, hasStatus: hasStatusRow, hasVersus: hasVersusRow) }

    var width: CGFloat { idealWidth * scale / idealScale }

    var height: CGFloat { Self.designHeight(rows: rows) * scale }

    var size: CGSize { CGSize(width: width, height: height) }

    /// Top-left of the card: under HSTracker's panel (or at the fallback spot), kept inside the
    /// game window. Fallback: 1 % from the left edge, resting on the bottom (8 % margin).
    var origin: CGPoint {
        let margin = canvas.width * Self.edgeMargin
        let x = left
        let y = trackerPanel == nil ? bottomLimit - height : min(wantedTop, bottomLimit - height)
        return CGPoint(x: max(margin, min(x, canvas.width - width - margin)), y: max(margin, y))
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
    @ObservedObject var tierImages: TierImageLoader = .shared

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
                                TierPaceBadge(tier: content.tier ?? 0, loader: tierImages)
                                VStack(alignment: .leading, spacing: 0) {
                                    if let turn = content.tierTurn {
                                        Text(verbatim: "on turn \(turn)").font(number).foregroundStyle(EdgeInkPalette.ink)
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
                    .foregroundStyle(content.hasLastBoard ? EdgeInkPalette.ink : EdgeInkPalette.dim)
                    .opacity(content.isLastBoardStale ? 0.55 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(height: NextOpponentLayout.rowHeight, alignment: .top)
            if rows.showsStatus {
                HStack(alignment: .top, spacing: 12) {
                    if let health = content.health {
                        block("HEALTH") {
                            HStack(spacing: 6) {
                                Text(verbatim: "\(health)").font(number).foregroundStyle(EdgeInkPalette.ink)
                                VStack(alignment: .leading, spacing: 0) {
                                    if let armor = content.armor {
                                        Text(verbatim: "+\(armor) armor").foregroundStyle(EdgeInkPalette.dim)
                                    }
                                    if let damage = content.lastCombatDamage {
                                        Text(verbatim: "down \(damage)").foregroundStyle(EdgeInkPalette.down)
                                    }
                                }
                                .font(secondary)
                                .lineLimit(1)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(healthAccessibility(health))
                        }
                    }
                    if let triples = content.triples {
                        block("TRIPLES") {
                            Text(verbatim: triples).font(number).foregroundStyle(EdgeInkPalette.ink)
                        }
                    }
                }
                .frame(height: NextOpponentLayout.rowHeight, alignment: .top)
            }
            if rows.showsVersus, content.hasFightWithYou {
                block("VS YOU") {
                    VStack(alignment: .leading, spacing: 1) {
                        if let fight = content.beatYou { Text(verbatim: Self.versusText(fight, subject: "Beat you")) }
                        if let fight = content.youBeatThem { Text(verbatim: Self.versusText(fight, subject: "You beat them")) }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(EdgeInkPalette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
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

    static func versusText(_ fight: FightWithYou, subject: String) -> String {
        "\(subject) · turn \(fight.turn) (−\(fight.damage))"
    }

    private func healthAccessibility(_ health: Int) -> String {
        var parts = ["\(health) health"]
        if let armor = content.armor { parts.append("\(armor) armor") }
        if let damage = content.lastCombatDamage { parts.append("took \(damage) in the last combat") }
        return parts.joined(separator: ", ")
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

    private func ratingLine(showsRank: Bool) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: content.mmr)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(content.mmr == NextOpponentContent.dash ? EdgeInkPalette.dim : EdgeInkPalette.gold)
            if let change = content.mmrChange {
                Text(verbatim: "\(change.delta > 0 ? "▲" : "▼")\(abs(change.delta))")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(change.delta > 0 ? EdgeInkPalette.gain : EdgeInkPalette.loss)
                Text(verbatim: change.window).font(secondary).foregroundStyle(EdgeInkPalette.dim)
                    .accessibilityLabel("rating \(change.delta > 0 ? "up" : "down") \(abs(change.delta)) \(change.window)")
            }
            if showsRank, let rank = content.rank {
                Text(verbatim: rank).font(secondary).foregroundStyle(EdgeInkPalette.dim)
            }
        }
        .fixedSize()
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
                ViewThatFits(in: .horizontal) {
                    ratingLine(showsRank: true)
                    ratingLine(showsRank: false)
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
