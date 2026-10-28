import CoreGraphics

/// Battlegrounds leaderboard slot geometry, derived from HSTracker's
/// leaderboard layout (MIT, © HearthSim; see THIRD_PARTY_NOTICES.md).
/// Positions are fractions of the game's content area, so they scale with it.
struct LeaderboardLayout {
    let canvasSize: CGSize
    /// 1-based leaderboard place of the next opponent, whose portrait sticks out
    /// of the rail; 0 when unknown.
    let nextOpponentPlace: Int

    static let slots = 8

    // HSTracker's leftAdjust and nextOpponentRightAdjust.
    private static let leftAdjust: CGFloat = 0.0017
    private static let nextOpponentRightAdjust: CGFloat = 0.023

    var tileHeight: CGFloat { canvasSize.height * 0.69 / CGFloat(Self.slots) }
    var tileWidth: CGFloat { tileHeight }

    /// Top edge of the portrait in `slot` (0 = first place).
    func top(for slot: Int) -> CGFloat {
        canvasSize.height * 0.15 + tileHeight * CGFloat(slot)
    }

    /// Left edge of the portrait in `slot`, inside the centered 4:3 play area.
    func left(for slot: Int) -> CGFloat {
        var left = CGFloat(Self.slots / 2 - slot) * Self.leftAdjust
        if slot == nextOpponentPlace - 1 {
            left += Self.nextOpponentRightAdjust
        }
        return Self.scaledX(left, width: canvasSize.width, height: canvasSize.height)
    }

    /// As HSTracker's SizeHelper.getScaledXPos: maps a fraction of the 4:3 area to window x.
    static func scaledX(_ fraction: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        let ratio = (4.0 / 3.0) / (width / height)
        return width * ratio * fraction + width * (1 - ratio) / 2
    }
}
