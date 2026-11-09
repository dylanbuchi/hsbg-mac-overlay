import SwiftUI

/// "DARK GIFTS 2 left" next to the Dark Discovery button: how many Dark Discoveries you can still use
/// this game. Only the count is shown; the log does not say which gifts can still appear.
enum DarkGiftCounterRules {
    /// Hidden outside Dark Gifts lobbies, once all uses are spent, and whenever the labels hide.
    static func visibleCount(usesLeft: Int?, showsTags: Bool) -> Int? {
        guard showsTags, let usesLeft, usesLeft > 0 else { return nil }
        return usesLeft
    }

    // The Dark Discovery button on the board's right rail, measured on a 1600x861 game window
    // (2026-11): center as a fraction of the 4:3 play area (x) and of the height (y), radius of the ring.
    static let buttonX: CGFloat = 0.953
    static let buttonY: CGFloat = 0.282
    static let buttonRadius: CGFloat = 0.044

    /// Just right of the Dark Discovery button; below it when the window is too narrow (about 4:3).
    static func center(canvas: CGSize, size: CGSize) -> CGPoint {
        let h = canvas.height
        let x = LeaderboardLayout.scaledX(buttonX, width: canvas.width, height: h)
        let y = h * buttonY
        let reach = h * buttonRadius + h * 0.012
        let margin: CGFloat = 4
        let beside = x + reach + size.width / 2
        if beside + size.width / 2 <= canvas.width - margin {
            return CGPoint(x: beside, y: y)
        }
        return CGPoint(x: min(max(x, size.width / 2 + margin), canvas.width - size.width / 2 - margin),
                       y: y + reach + size.height / 2)
    }
}

struct DarkGiftCounter: View {
    let usesLeft: Int
    static let size = CGSize(width: 76, height: 52)

    var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: "DARK GIFTS")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(EdgeInkPalette.dim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "\(usesLeft)")
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(EdgeInkPalette.gold)
                Text(verbatim: "left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EdgeInkPalette.ink)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(EdgeInkPalette.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EdgeInkPalette.gold.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dark Gifts: \(usesLeft) left")
    }
}
