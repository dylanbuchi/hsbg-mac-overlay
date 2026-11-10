import SwiftUI

/// "DARK GIFTS 2 left" under the Dark Discovery button: how many Dark Discoveries you can still use
/// this game. Only the count is shown; the log does not say which gifts can still appear.
enum DarkGiftCounterRules {
    /// Hidden outside Dark Gifts lobbies, once all uses are spent, and whenever the labels hide.
    static func visibleCount(usesLeft: Int?, showsTags: Bool) -> Int? {
        guard showsTags, let usesLeft, usesLeft > 0 else { return nil }
        return usesLeft
    }

    // The Dark Discovery button on the board's right rail, measured on 1600x861 and 2000x1093 game windows
    // (2026-11): center as a fraction of the 4:3 play area (x) and of the height (y), radius of the ring.
    static let buttonX: CGFloat = 0.947
    static let buttonY: CGFloat = 0.282
    static let buttonRadius: CGFloat = 0.044

    /// Grows with the board, like the leaderboard labels; 1 on the window the button was measured on.
    static func scale(canvas: CGSize) -> CGFloat {
        min(max(canvas.height / 861, 0.75), 1.8)
    }

    /// The box at scale 1. Kept here, outside the main-actor view, so layout code can read it anywhere.
    static let baseSize = CGSize(width: 76, height: 52)

    static func size(canvas: CGSize) -> CGSize {
        let scale = scale(canvas: canvas)
        return CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
    }

    /// Centered just under the Dark Discovery button, on the empty rail: clear of the board,
    /// the shop and HSTracker's right-hand panels.
    static func center(canvas: CGSize, size: CGSize) -> CGPoint {
        let h = canvas.height
        let x = LeaderboardLayout.scaledX(buttonX, width: canvas.width, height: h)
        let top = h * buttonY + h * buttonRadius + h * 0.015
        let margin: CGFloat = 4
        return CGPoint(x: min(max(x, size.width / 2 + margin), canvas.width - size.width / 2 - margin),
                       y: top + size.height / 2)
    }
}

struct DarkGiftCounter: View {
    let usesLeft: Int
    var scale: CGFloat = 1
    var body: some View {
        VStack(spacing: 1 * scale) {
            Text(verbatim: "DARK GIFTS")
                .font(.system(size: 9.5 * scale, weight: .semibold))
                .tracking(0.6 * scale)
                .foregroundStyle(EdgeInkPalette.dim)
            HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                Text(verbatim: "\(usesLeft)")
                    .font(.system(size: 20 * scale, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(EdgeInkPalette.gold)
                Text(verbatim: "left")
                    .font(.system(size: 11 * scale, weight: .medium))
                    .foregroundStyle(EdgeInkPalette.ink)
            }
        }
        .frame(width: DarkGiftCounterRules.baseSize.width * scale, height: DarkGiftCounterRules.baseSize.height * scale)
        .background(EdgeInkPalette.cardBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 8 * scale))
        .overlay(RoundedRectangle(cornerRadius: 8 * scale).strokeBorder(EdgeInkPalette.gold.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dark Gifts: \(usesLeft) left")
    }
}
