import CoreGraphics
import Foundation

/// Where the user put the NEXT OPPONENT card, relative to the game window, so it survives resizes,
/// fullscreen toggles and restarts.
struct CardPlacement: Codable, Equatable {
    /// Card's left edge as a fraction of the window width, top edge as a fraction of its height.
    var x: Double
    var y: Double
    /// Card width as a fraction of the window height: the card grows and shrinks with the window.
    var size: Double

    static let scaleRange: ClosedRange<CGFloat> = 0.7...1.6

    func scale(in canvas: CGSize) -> CGFloat {
        let wanted = CGFloat(size) * canvas.height / NextOpponentLayout.designWidth
        return min(max(wanted, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    func origin(in canvas: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * canvas.width, y: CGFloat(y) * canvas.height)
    }

    /// The placement for a card drawn at `origin` and `scale` (scale clamped to the allowed range).
    static func make(origin: CGPoint, scale: CGFloat, canvas: CGSize) -> CardPlacement {
        let scale = min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
        guard canvas.width > 0, canvas.height > 0 else { return CardPlacement(x: 0, y: 0, size: 0) }
        return CardPlacement(x: Double(origin.x / canvas.width), y: Double(origin.y / canvas.height),
                             size: Double(NextOpponentLayout.designWidth * scale / canvas.height))
    }
}

/// Saved placements, one per window shape (16:9, 16:10, 4:3 or the exact ratio), plus the last one saved,
/// which stands in for shapes the user has not placed the card on yet.
struct CardPlacements: Codable, Equatable {
    var byShape: [String: CardPlacement] = [:]
    var last: CardPlacement?

    static func shape(of canvas: CGSize) -> String {
        guard canvas.height > 0 else { return "none" }
        let ratio = canvas.width / canvas.height
        for (name, value) in [("16:9", 16.0 / 9.0), ("16:10", 1.6), ("4:3", 4.0 / 3.0), ("21:9", 21.0 / 9.0)]
        where abs(ratio - value) < 0.04 { return name }
        return String(format: "%.2f", ratio)
    }

    func placement(for canvas: CGSize) -> CardPlacement? {
        byShape[Self.shape(of: canvas)] ?? last
    }

    mutating func save(_ placement: CardPlacement, for canvas: CGSize) {
        byShape[Self.shape(of: canvas)] = placement
        last = placement
    }

    var isEmpty: Bool { byShape.isEmpty && last == nil }

    static let defaultsKey = "cardPlacements"

    static func load(_ defaults: UserDefaults = .standard) -> CardPlacements {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(CardPlacements.self, from: data) else { return CardPlacements() }
        return decoded
    }

    func store(_ defaults: UserDefaults = .standard) {
        if isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
