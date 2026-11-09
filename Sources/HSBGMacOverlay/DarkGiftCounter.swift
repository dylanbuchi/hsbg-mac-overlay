import SwiftUI

/// "DARK GIFTS 2 left" on the right edge: how many Dark Discoveries you can still use
/// this game. Only the count is shown; the log does not say which gifts can still appear.
enum DarkGiftCounterRules {
    /// Hidden outside Dark Gifts lobbies, once all uses are spent, and whenever the labels hide.
    static func visibleCount(usesLeft: Int?, showsTags: Bool) -> Int? {
        guard showsTags, let usesLeft, usesLeft > 0 else { return nil }
        return usesLeft
    }

    /// Right edge, a bit above the middle, clear of the board and the shop.
    static func center(canvas: CGSize, size: CGSize) -> CGPoint {
        CGPoint(x: canvas.width - size.width / 2 - 14, y: canvas.height * 0.42)
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
