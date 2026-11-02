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

/// The tribe's badge: HSTracker's own round picture when its install has one, else a dark disc with a
/// coloured ring and glyph (our own drawing). The only place that draws it.
struct TribeIcon: View {
    let tribe: String
    let size: CGFloat
    var art: TribeArt = .shared

    var body: some View {
        let style = TribeStyle.style(for: tribe)
        Group {
            if let image = art.image(for: tribe) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    // A ring of the tribe's colour keeps the picture apart from light and dark backgrounds alike.
                    .overlay(Circle().strokeBorder(style.color, lineWidth: max(size * 0.07, 1)))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(Color.black.opacity(0.78))
                    .overlay(Circle().strokeBorder(style.color, lineWidth: max(size * 0.09, 1)))
                    .overlay(Image(systemName: style.symbol)
                        .resizable().aspectRatio(contentMode: .fit)
                        .foregroundStyle(style.color)
                        .padding(size * 0.22))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(TribeNames.plural(tribe))
    }
}

/// Up to two tribes under the tier shield: icon and how many minions of it.
struct TribeBadges: View {
    /// A single minion says little about a build: the icon stands alone until there are two.
    nonisolated static func countText(_ count: Int) -> String? { count >= 2 ? "\(count)" : nil }

    let tribes: [TribeCount]
    let size: CGFloat
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.12) {
            ForEach(tribes, id: \.tribe) { entry in
                HStack(spacing: size * 0.14) {
                    TribeIcon(tribe: entry.tribe, size: size)
                    if let count = Self.countText(entry.count) {
                        Text(verbatim: count)
                            .font(.system(size: max(size * 0.8, EdgeInkMetrics.minimumFont), weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(TribeNames.plural(entry.tribe)) \(entry.count)")
            }
        }
        .shadow(color: .black, radius: 0.5, y: 1)
        .shadow(color: .black.opacity(0.9), radius: 2)
        .opacity(isStale ? 0.65 : 1)
    }
}
