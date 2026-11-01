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

    let width: CGFloat

    var nameSize: CGFloat { max(width * 0.126, Self.minimumFont) }
    var lineSize: CGFloat { max(width * 0.098, Self.minimumFont) }
    var gap: CGFloat { width * 0.014 }
    var sideInset: CGFloat { width * 0.06 }
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
    /// Free width for the text block.
    var textWidth: CGFloat { width - 2 * sideInset }

    /// Rough digit width of the rounded, monospaced-digit face.
    private func textWidth(_ characters: Int) -> CGFloat { CGFloat(characters) * lineSize * 0.6 }

    /// The most detail whose estimated width fits on line 2. Drop order: record, then
    /// streak, then (below `minimumLineWidth`) everything.
    func detail(mmr: String, record: String?, streakDigits: Int?) -> Detail {
        guard width >= Self.minimumLineWidth else { return .none }
        let minimumGap = width * 0.04
        let mmrWidth = textWidth(mmr.count)
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
        let detail = metrics.detail(mmr: content.mmr ?? "—",
                                    record: content.record, streakDigits: content.streak.map { String($0.count).count })
        ZStack(alignment: .topLeading) {
            veil(metrics)
            text(metrics, detail: detail)
                .padding(.horizontal, metrics.sideInset)
                .padding(.top, metrics.topInset)
                .compositingGroup()
                .shadow(color: .black, radius: 0.5, x: 0, y: 0)
                .shadow(color: .black, radius: 0.5, x: 0, y: 1)
                .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 0)
        }
        .frame(width: width, height: metrics.veilHeight, alignment: .topLeading)
    }

    private func veil(_ metrics: EdgeInkMetrics) -> some View {
        TopRoundedRectangle(radius: metrics.cornerRadius)
            .fill(LinearGradient(stops: [
                .init(color: (content.isLocalPlayer ? EdgeInkPalette.veilYou : EdgeInkPalette.veil).opacity(0.86), location: 0),
                .init(color: (content.isLocalPlayer ? EdgeInkPalette.veilYou : EdgeInkPalette.veil).opacity(0.62), location: 0.45),
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
            if detail != .none {
                HStack(spacing: 0) {
                    Text(verbatim: content.mmr ?? "—")
                        .foregroundStyle(content.mmr == nil ? EdgeInkPalette.dim
                                         : content.isLeader ? EdgeInkPalette.leaderGold : EdgeInkPalette.gold)
                        .fontWeight(content.isLeader && content.mmr != nil ? .heavy : nil)
                        .accessibilityLabel(content.isLeader ? "\(content.mmr ?? ""), highest rating in the lobby" : (content.mmr ?? "no rating"))
                    Spacer(minLength: metrics.recordGap)
                    HStack(spacing: metrics.recordGap) {
                        if detail == .full, let record = content.record {
                            Text(verbatim: record).foregroundStyle(EdgeInkPalette.ink)
                        }
                        if detail >= .mmrAndStreak, let streak = content.streak {
                            StreakMark(isLoss: streak.isLoss, count: streak.count,
                                       arrowSize: metrics.arrowSize, gap: metrics.arrowGap)
                        }
                    }
                }
                .font(.system(size: metrics.lineSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            }
            if detail != .none, let triples = content.triples {
                HStack(spacing: metrics.arrowGap * 2) {
                    Text(verbatim: "🪙")
                    Text(verbatim: "\(triples)").foregroundStyle(EdgeInkPalette.gold)
                }
                .font(.system(size: metrics.lineSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(triples) triples")
            }
        }
    }
}
