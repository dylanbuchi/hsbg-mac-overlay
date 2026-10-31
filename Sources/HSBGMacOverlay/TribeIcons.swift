import Foundation
import SwiftUI

struct TribeCount: Equatable {
    let tribe: String
    let count: Int
}

enum TribeSummary {
    /// The biggest tribe on the last board seen, plus a second one when it is also a real
    /// presence (3 or more). Ties go to the tribe name, so the order is stable.
    static func main(from tribes: [String: Int]) -> [TribeCount] {
        let ranked = tribes.filter { $0.value > 0 }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        return ranked.enumerated().compactMap { index, entry in
            guard index == 0 || (index == 1 && entry.value >= 3) else { return nil }
            return TribeCount(tribe: entry.key, count: entry.value)
        }
    }

    /// A board seen more than two turns ago is shown faded.
    static func isStale(lastSeenTurn: Int?, currentTurn: Int) -> Bool {
        lastSeenTurn.map { currentTurn - $0 > 2 } ?? false
    }
}

/// One colour and one simple glyph per tribe (Apple SF Symbols, no game art). The glyph
/// differs from tribe to tribe, so colour is never the only clue.
struct TribeStyle: Equatable {
    let symbol: String
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    static let all: [String: TribeStyle] = [
        "BEAST": TribeStyle(symbol: "pawprint.fill", red: 0.95, green: 0.55, blue: 0.2),
        "DEMON": TribeStyle(symbol: "flame.fill", red: 0.85, green: 0.2, blue: 0.3),
        "DRAGON": TribeStyle(symbol: "bolt.fill", red: 0.35, green: 0.8, blue: 0.4),
        "ELEMENTAL": TribeStyle(symbol: "tornado", red: 0.35, green: 0.65, blue: 1.0),
        "MECHANICAL": TribeStyle(symbol: "gearshape.fill", red: 0.7, green: 0.75, blue: 0.8),
        "MURLOC": TribeStyle(symbol: "drop.fill", red: 0.2, green: 0.8, blue: 0.8),
        "NAGA": TribeStyle(symbol: "water.waves", red: 0.45, green: 0.45, blue: 0.95),
        "PIRATE": TribeStyle(symbol: "flag.fill", red: 0.9, green: 0.78, blue: 0.4),
        "QUILBOAR": TribeStyle(symbol: "mountain.2.fill", red: 0.85, green: 0.5, blue: 0.6),
        "UNDEAD": TribeStyle(symbol: "moon.stars.fill", red: 0.65, green: 0.45, blue: 0.85),
        "ABERRATION": TribeStyle(symbol: "eye.fill", red: 0.9, green: 0.3, blue: 0.8),
        "ALL": TribeStyle(symbol: "star.fill", red: 1.0, green: 1.0, blue: 1.0),
    ]

    static let unknown = TribeStyle(symbol: "questionmark", red: 0.6, green: 0.6, blue: 0.6)

    static func style(for tribe: String) -> TribeStyle { all[tribe] ?? unknown }
}

/// The tribe's badge: a dark disc with a coloured ring and glyph. The only place that draws
/// it, so downloaded art can replace the body later without touching the callers.
struct TribeIcon: View {
    let tribe: String
    let size: CGFloat

    var body: some View {
        let style = TribeStyle.style(for: tribe)
        Circle()
            .fill(Color.black.opacity(0.78))
            .overlay(Circle().strokeBorder(style.color, lineWidth: max(size * 0.09, 1)))
            .overlay(Image(systemName: style.symbol)
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(style.color)
                .padding(size * 0.22))
            .frame(width: size, height: size)
            .accessibilityLabel(TribeNames.plural(tribe))
    }
}

/// Up to two tribes under the tier shield: icon and how many minions of it.
struct TribeBadges: View {
    let tribes: [TribeCount]
    let size: CGFloat
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.12) {
            ForEach(tribes, id: \.tribe) { entry in
                HStack(spacing: size * 0.14) {
                    TribeIcon(tribe: entry.tribe, size: size)
                    Text(verbatim: "\(entry.count)")
                        .font(.system(size: max(size * 0.8, EdgeInkMetrics.minimumFont), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .shadow(color: .black, radius: 0.5, y: 1)
        .shadow(color: .black.opacity(0.9), radius: 2)
        .opacity(isStale ? 0.65 : 1)
    }
}

struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for point in 0..<10 {
            let radius = point.isMultiple(of: 2) ? outer : outer * 0.42
            let angle = -Double.pi / 2 + Double(point) * Double.pi / 5
            let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.08))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.08),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.55))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.85))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55),
                          control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.85))
        path.closeSubpath()
        return path
    }
}

/// Tavern tier as a small shield with one gold star per tier (1-6). The only place that draws
/// it, so downloaded art can replace the body later. Unknown tiers draw nothing.
struct TierShield: View {
    let tier: Int?
    let height: CGFloat

    /// Stars per row, top to bottom: 1 → [1], 3 → [2, 1], 6 → [3, 3]. Empty when unknown.
    static func starRows(for tier: Int?) -> [Int] {
        switch tier ?? 0 {
        case 1: return [1]
        case 2: return [2]
        case 3: return [2, 1]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6...: return [3, 3]
        default: return []
        }
    }

    var body: some View {
        let rows = Self.starRows(for: tier)
        let starSize = height * 0.22
        ZStack {
            ShieldShape()
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.2, blue: 0.5), Color(red: 0.18, green: 0.1, blue: 0.3)],
                                     startPoint: .top, endPoint: .bottom))
            ShieldShape().stroke(EdgeInkPalette.gold, lineWidth: max(height * 0.06, 1))
            VStack(spacing: starSize * 0.15) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, count in
                    HStack(spacing: starSize * 0.1) {
                        ForEach(0..<count, id: \.self) { _ in
                            Star().fill(EdgeInkPalette.gold).frame(width: starSize, height: starSize)
                        }
                    }
                }
            }
            .offset(y: -height * 0.04)
        }
        .frame(width: height * 0.82, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.map { "Tavern tier \($0)" } ?? "Tavern tier unknown")
    }
}
