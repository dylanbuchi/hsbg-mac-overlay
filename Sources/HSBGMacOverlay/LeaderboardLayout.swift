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

    /// Where the leftmost label starts, less a small gap: the card must stay left of it.
    var labelsLeftEdge: CGFloat {
        (0..<Self.slots).map { left(for: $0) }.min().map { $0 + tileHeight * 0.13 - canvasSize.width * 0.005 } ?? 0
    }

    /// As HSTracker's SizeHelper.getScaledXPos: maps a fraction of the 4:3 area to window x.
    static func scaledX(_ fraction: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        let ratio = (4.0 / 3.0) / (width / height)
        return width * ratio * fraction + width * (1 - ratio) / 2
    }
}

enum LeaderboardSlots {
    /// The game has put this player on the leaderboard: a place and a tavern tier. Before that (hero pick,
    /// a lobby still loading) nothing is drawn, so no label floats on the empty rail.
    static func isOnRail(_ player: BattlegroundsPlayer) -> Bool {
        player.placement != nil && (player.tavernTier ?? 0) > 0
    }

    /// Zero-based slot for each player. Players without a place yet take the lowest free
    /// slots in order, so two of them never share a portrait while the lobby is loading.
    static func assign(placements: [Int?]) -> [Int] {
        var taken = Set(placements.compactMap { $0 }.filter { (1...LeaderboardLayout.slots).contains($0) }.map { $0 - 1 })
        var nextFree = 0
        return placements.map { placement in
            if let placement, placement > 0 { return placement - 1 }
            while taken.contains(nextFree) { nextFree += 1 }
            taken.insert(nextFree)
            return nextFree
        }
    }
}

enum ScreenMatch {
    /// A full-screen game window is not always exactly the screen: scaled displays round,
    /// and on a notch Mac the window can start below the camera housing.
    static func isFullscreen(_ frame: CGRect, screenFrames: [CGRect], tolerance: CGFloat = 4) -> Bool {
        screenFrames.contains { screen in
            abs(frame.minX - screen.minX) <= tolerance && abs(frame.maxX - screen.maxX) <= tolerance
                && abs(frame.minY - screen.minY) <= tolerance && abs(frame.maxY - screen.maxY) <= tolerance
        }
    }
}
