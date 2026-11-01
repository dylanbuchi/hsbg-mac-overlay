import Foundation
import SwiftUI

/// Sizes of the "Edge Ink" label drawn over the top of a leaderboard portrait.
/// Everything is a fraction of `width` (the portrait art width), so the label
/// scales with the window. Text never goes below `minimumFont`.
struct EdgeInkMetrics: Equatable {
    /// What fits on the second line; each step down drops the least important part first.
    enum Detail: Int, Comparable {
        case none, mmr, mmrAndStreak, full
        static func < (lhs: Detail, rhs: Detail) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let minimumFont: CGFloat = 8
    /// Below this width the second line is dropped altogether.
    static let minimumLineWidth: CGFloat = 40
    /// Sizes line 2 steps down through when it does not fit, largest first; the last one is used regardless.
    static let lineScales: [CGFloat] = [1, 0.9, 0.8, 0.7]

    let width: CGFloat

    var nameSize: CGFloat { max(width * 0.126, Self.minimumFont) }
    var lineSize: CGFloat { max(width * 0.098, Self.minimumFont) }
    var gap: CGFloat { width * 0.014 }
    var sideInset: CGFloat { width * 0.06 }
    /// The text starts after the game's own rank medal (the 1-8 gem on the portrait's top-left corner).
    var medalInset: CGFloat { width * 0.22 }
    var topInset: CGFloat { width * 0.04 }
    var veilHeight: CGFloat { width * 0.53 }
    var veilInset: CGFloat { width * 0.02 }
    /// The veil reaches past the art on both sides so the game's own name text
    /// (visible before a hero is picked) never peeks out beside it.
    var veilOutset: CGFloat { width * 0.04 }
    var cornerRadius: CGFloat { width * 0.07 }
    var edgeFade: CGFloat { 0.07 }
    var recordGap: CGFloat { width * 0.02 }
    var arrowSize: CGFloat { lineSize * 0.6 }
    var arrowGap: CGFloat { width * 0.006 }
    var diamondSize: CGFloat { width * 0.046 }
    var dotSize: CGFloat { width * 0.046 }
    var dotGap: CGFloat { width * 0.02 }
    /// Free width for the text block, between the rank medal and the right edge.
    var textWidth: CGFloat { width - medalInset - sideInset }

    /// Rough digit width of the rounded, monospaced-digit face.
    private func textWidth(_ characters: Int) -> CGFloat { CGFloat(characters) * lineSize * 0.6 }

    /// The most detail whose estimated width fits on line 2. Drop order: record, then
    /// streak, then (below `minimumLineWidth`) everything. An unknown MMR (nil) takes no room.
    func detail(mmr: String?, record: String?, streakDigits: Int?) -> Detail {
        guard width >= Self.minimumLineWidth else { return .none }
        let minimumGap = mmr == nil ? 0 : width * 0.04
        let mmrWidth = textWidth(mmr?.count ?? 0)
        let streakWidth = streakDigits.map { arrowSize + arrowGap + textWidth($0) }
        let recordWidth = record.map { textWidth($0.count) }
        if let recordWidth {
            let right = recordWidth + (streakWidth.map { recordGap + $0 } ?? 0)
            if mmrWidth + minimumGap + right <= textWidth { return .full }
        }
        if let streakWidth, mmrWidth + minimumGap + streakWidth <= textWidth { return .mmrAndStreak }
        return mmrWidth <= textWidth ? .mmr : .none
    }
}

enum RatingFormat {
    private static let locale = Locale(identifier: "en_US")
    /// 12691 → "12,691", in every locale so the width estimate holds.
    static func text(_ rating: Int) -> String { rating.formatted(.number.locale(locale)) }
}

struct StreakRun: Equatable {
    var isLoss: Bool
    var count: Int
}

/// What the portrait label shows for one player, before any fitting.
struct EdgeInkContent: Equatable {
    var name: String
    var mmr: String?
    var record: String?
    /// Run of 2+ rounds: direction and length. The arrow shape carries the meaning, not the colour.
    var streak: StreakRun?
    var isLocalPlayer: Bool
    var isLeader: Bool
    /// Triples made this game; nil when none.
    var triples: Int?

    init(player: BattlegroundsPlayer, isLeader: Bool) {
        name = player.name.split(separator: "#").first.map(String.init) ?? player.name
        mmr = player.rating.map(RatingFormat.text)
        record = player.wins + player.losses > 0 ? "\(player.wins)–\(player.losses)" : nil
        if player.winStreak >= 2 {
            streak = StreakRun(isLoss: false, count: player.winStreak)
        } else if player.lossStreak >= 2 {
            streak = StreakRun(isLoss: true, count: player.lossStreak)
        }
        isLocalPlayer = player.isLocalPlayer
        self.isLeader = isLeader
        triples = (player.triples ?? 0) > 0 ? player.triples : nil
    }
}

enum EdgeInkPalette {
    static let ink = Color.white
    static let gold = Color(red: 0xF0 / 255, green: 0xDC / 255, blue: 0xA8 / 255)
    /// The lobby's top rating: a clear step brighter than `gold`.
    static let leaderGold = Color(red: 0xFF / 255, green: 0xCB / 255, blue: 0x2E / 255)
    static let dim = Color(red: 0xA6 / 255, green: 0x9F / 255, blue: 0xB4 / 255)
    static let up = Color(red: 0xFF / 255, green: 0xC2 / 255, blue: 0x66 / 255)
    static let down = Color(red: 0x9C / 255, green: 0xC2 / 255, blue: 0xFF / 255)
    /// Rating up and down on the card: green and red, always with an arrow.
    static let gain = Color(red: 0x6E / 255, green: 0xDB / 255, blue: 0x8A / 255)
    static let loss = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x6B / 255)
    static let you = Color(red: 0x7F / 255, green: 0xDB / 255, blue: 0xF5 / 255)
    static let veil = Color(red: 0x06 / 255, green: 0x04 / 255, blue: 0x0A / 255)
    static let veilYou = Color(red: 0x04 / 255, green: 0x10 / 255, blue: 0x18 / 255)
    static let cardBackground = Color(red: 0x0F / 255, green: 0x0C / 255, blue: 0x15 / 255)
}

/// Rounded on the top corners only (macOS 13 has no UnevenRoundedRectangle).
struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct Triangle: Shape {
    var pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// ▲ (not lost) or ▼ (lost) followed by the run length.
struct StreakMark: View {
    let isLoss: Bool
    let count: Int
    let arrowSize: CGFloat
    let gap: CGFloat

    var body: some View {
        HStack(spacing: gap) {
            Triangle(pointsUp: !isLoss)
                .fill(isLoss ? EdgeInkPalette.down : EdgeInkPalette.up)
                .frame(width: arrowSize, height: arrowSize * 0.85)
            Text(verbatim: "\(count)")
                .foregroundStyle(isLoss ? EdgeInkPalette.down : EdgeInkPalette.up)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoss ? "\(count) rounds lost in a row" : "\(count) rounds in a row not lost")
    }
}

/// Soft dark vignette with outlined SF type over the top of a portrait; no box, and wide
/// enough to cover whatever name text the game draws underneath.
struct EdgeInkLabel: View {
    let content: EdgeInkContent
    /// Portrait art width.
    let width: CGFloat

    var body: some View {
        let metrics = EdgeInkMetrics(width: width)
        let detail = metrics.detail(mmr: content.mmr,
                                    record: content.record, streakDigits: content.streak.map { String($0.count).count })
        ZStack(alignment: .topLeading) {
            veil(metrics)
            text(metrics, detail: detail)
                .padding(.leading, metrics.medalInset)
                .padding(.trailing, metrics.sideInset)
                .padding(.top, metrics.topInset)
                .frame(width: width, alignment: .topLeading)
                .compositingGroup()
                // A thin dark outline on every side, then a soft halo: readable on bright art too.
                .shadow(color: .black, radius: 0, x: 0.75, y: 0.75)
                .shadow(color: .black, radius: 0, x: -0.75, y: -0.75)
                .shadow(color: .black, radius: 0.5, x: 0, y: 1)
                .shadow(color: .black.opacity(0.9), radius: 2.5, x: 0, y: 0)
        }
        .frame(width: width, height: metrics.veilHeight, alignment: .topLeading)
    }

    private func veil(_ metrics: EdgeInkMetrics) -> some View {
        TopRoundedRectangle(radius: metrics.cornerRadius)
            .fill(LinearGradient(stops: [
                .init(color: (content.isLocalPlayer ? EdgeInkPalette.veilYou : EdgeInkPalette.veil).opacity(0.86), location: 0),
                .init(color: (content.isLocalPlayer ? EdgeInkPalette.veilYou : EdgeInkPalette.veil).opacity(0.7), location: 0.45),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: metrics.edgeFade),
                .init(color: .black, location: 1 - metrics.edgeFade),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
            .frame(width: width + 2 * metrics.veilOutset - 2 * metrics.veilInset, height: metrics.veilHeight)
            .offset(x: -metrics.veilOutset + metrics.veilInset)
    }

    /// Line 2 has something to show: the MMR, or (when it is unknown) a record or streak that fits.
    private func hasSecondLine(_ detail: EdgeInkMetrics.Detail) -> Bool {
        content.mmr != nil || (detail == .full && content.record != nil) || (detail >= .mmrAndStreak && content.streak != nil)
    }

    func detailLine(_ metrics: EdgeInkMetrics, detail: EdgeInkMetrics.Detail, scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            // No public rating: nothing, rather than a dash on every unlisted portrait.
            if let mmr = content.mmr {
                Text(verbatim: mmr)
                    .foregroundStyle(content.isLeader ? EdgeInkPalette.leaderGold : EdgeInkPalette.gold)
                    .fontWeight(content.isLeader ? .heavy : nil)
                    .accessibilityLabel(content.isLeader ? "\(mmr), highest rating in the lobby" : mmr)
                Spacer(minLength: metrics.recordGap * scale)
            }
            HStack(spacing: metrics.recordGap * scale) {
                if detail == .full, let record = content.record {
                    Text(verbatim: record).foregroundStyle(EdgeInkPalette.ink).fixedSize()
                }
                if detail >= .mmrAndStreak, let streak = content.streak {
                    StreakMark(isLoss: streak.isLoss, count: streak.count,
                               arrowSize: metrics.arrowSize * scale, gap: metrics.arrowGap * scale)
                }
            }
            if content.mmr == nil { Spacer(minLength: 0) }
        }
        .font(.system(size: metrics.lineSize * scale, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
    }

    private func text(_ metrics: EdgeInkMetrics, detail: EdgeInkMetrics.Detail) -> some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            HStack(spacing: metrics.dotGap) {
                Text(verbatim: content.name)
                    .font(.system(size: metrics.nameSize, weight: .bold))
                    .tracking(-metrics.nameSize * 0.015)
                    .foregroundStyle(EdgeInkPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if content.isLocalPlayer {
                    Circle().fill(EdgeInkPalette.you)
                        .frame(width: metrics.dotSize, height: metrics.dotSize)
                        .shadow(color: EdgeInkPalette.you.opacity(0.6), radius: metrics.width * 0.012)
                        .accessibilityLabel("You")
                }
            }
            if detail != .none, hasSecondLine(detail) {
                // The width estimate can be a little short (4-digit MMR, record and streak on a narrow
                // portrait): step the line down in size until it fits, so the record never truncates.
                ViewThatFits(in: .horizontal) {
                    ForEach(EdgeInkMetrics.lineScales, id: \.self) { scale in
                        detailLine(metrics, detail: detail, scale: scale)
                    }
                }
            }
            if detail != .none, let triples = content.triples {
                HStack(spacing: metrics.arrowGap * 2) {
                    // A drawn gold disc rather than an emoji: same look on every macOS, outlined like the other marks.
                    Circle()
                        .fill(EdgeInkPalette.gold)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: max(metrics.lineSize * 0.08, 0.75)))
                        .frame(width: metrics.lineSize * 0.72, height: metrics.lineSize * 0.72)
                    Text(verbatim: "\(triples)").foregroundStyle(EdgeInkPalette.gold)
                }
                .font(.system(size: metrics.lineSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(triples == 1 ? "1 triple made" : "\(triples) triples made")
            }
        }
    }
}
