import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct InGameOverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        GeometryReader { geometry in
            let layout = LeaderboardLayout(canvasSize: geometry.size,
                                           nextOpponentPlace: model.nextOpponentPlace)
            let tile = layout.tileHeight
            ZStack(alignment: .topLeading) {
                Color.clear
                let slots = LeaderboardSlots.assign(placements: model.lobby.players.map(\.placement))
                ForEach(Array(model.lobby.players.enumerated()), id: \.element.id) { index, player in
                    let slot = slots[index]
                    if (0..<LeaderboardLayout.slots).contains(slot) {
                        let left = layout.left(for: slot)
                        let top = layout.top(for: slot)
                        // No name means the lobby has not been read yet: show the tier alone.
                        if !player.name.isEmpty {
                            Nameplate(player: player, tile: tile)
                                .frame(width: tile * 0.74)
                                .offset(x: left + tile * 0.13, y: top + tile * 0.1)
                        }
                        if model.showsTierIcons, let icon = TierIcons.image(for: player.tavernTier) {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: tile * 0.3)
                                .shadow(color: .black.opacity(0.6), radius: tile * 0.02)
                                .offset(x: left + tile * 0.9, y: top + tile * 0.06)
                        } else {
                            TierBadge(tier: player.tavernTier, tile: tile)
                                .offset(x: left + tile * 0.92, y: top + tile * 0.1)
                        }
                        // Record, streak and triples stack under the tier, beside the portrait.
                        PlayerStats(player: player, tile: tile, currentTurn: model.turn)
                            .offset(x: left + tile * 0.9, y: top + tile * 0.4)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .opacity(model.showsTags ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: model.showsTags)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

/// Name over MMR across the top of a leaderboard portrait. Sizes follow the tile.
struct Nameplate: View {
    let player: BattlegroundsPlayer
    let tile: CGFloat

    private var displayName: String {
        player.name.split(separator: "#").first.map(String.init) ?? player.name
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: displayName)
                .font(.system(size: tile * 0.105, weight: .bold))
                .minimumScaleFactor(0.6)
            Text(verbatim: player.rating.map(String.init) ?? "—")
                .font(.system(size: tile * 0.1, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.85))
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.vertical, tile * 0.015)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: tile * 0.04))
    }
}

/// Line 1: combat record (rounds without a loss - losses) and a flame for a run of
/// 2+ rounds without losing. Line 2: main tribe(s) from the last board fought,
/// dimmed when it is more than two turns old, triples, and the turn the current
/// tier was reached. Each part appears once it has data.
struct PlayerStats: View {
    let player: BattlegroundsPlayer
    let tile: CGFloat
    let currentTurn: Int

    static let tribeIcons = [
        "BEAST": "🦁", "DEMON": "😈", "DRAGON": "🐉", "ELEMENTAL": "🌪️", "MECHANICAL": "⚙️",
        // Bright icons only: the chips are dark (a black pirate flag disappeared).
        "MURLOC": "🐟", "NAGA": "🐍", "PIRATE": "🦜", "QUILBOAR": "🐗", "UNDEAD": "💀",
        "ABERRATION": "👁️", "ALL": "🌈",
    ]

    /// The biggest tribe, plus a second one when it is also a real presence.
    private var mainTribes: [(icon: String, count: Int)] {
        let ranked = player.lastSeenTribes.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        return ranked.enumerated().compactMap { index, entry in
            guard index == 0 || (index == 1 && entry.value >= 3) else { return nil }
            return (Self.tribeIcons[entry.key] ?? "❔", entry.value)
        }
    }

    private var isTribeStale: Bool {
        guard let seen = player.lastSeenTurn else { return false }
        return currentTurn - seen > 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tile * 0.03) {
            if player.wins + player.losses > 0 {
                chip {
                    Text(verbatim: "\(player.wins)-\(player.losses)")
                        .monospacedDigit()
                    if player.streak >= 2 {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red],
                                                            startPoint: .top, endPoint: .bottom))
                        Text(verbatim: "\(player.streak)")
                            .monospacedDigit()
                            .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.35))
                    }
                }
            }
            let tribes = mainTribes
            let triples = player.triples ?? 0
            let levelTurn = (player.tavernTier ?? 0) >= 2 ? player.tierReachedTurn : nil
            if !tribes.isEmpty || triples > 0 || levelTurn != nil {
                chip {
                    ForEach(tribes, id: \.icon) { tribe in
                        HStack(spacing: tile * 0.01) {
                            Text(verbatim: tribe.icon)
                                .font(.system(size: tile * 0.12))
                            Text(verbatim: "\(tribe.count)").monospacedDigit()
                        }
                        .opacity(isTribeStale ? 0.65 : 1)
                    }
                    if triples > 0 {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.35))
                        Text(verbatim: "\(triples)").monospacedDigit()
                    }
                    if let levelTurn {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Color(white: 0.75))
                        Text(verbatim: "\(levelTurn)").monospacedDigit()
                            .foregroundStyle(Color(white: 0.85))
                    }
                }
            }
        }
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: tile * 0.025) {
            content()
        }
        .font(.system(size: tile * 0.095, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, tile * 0.04)
        .padding(.vertical, tile * 0.012)
        .background(Color.black.opacity(0.65), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .fixedSize()
    }
}

/// The game's tavern tier shields, read from the installed HSTracker at runtime
/// (they are Blizzard art, so they are not bundled here). Nil falls back to TierBadge.
@MainActor
enum TierIcons {
    private static var directory: String { AppLocations.tierIconsDirectory }
    private static var cache: [Int: NSImage] = [:]

    static func image(for tier: Int?) -> NSImage? {
        guard let tier, (1...6).contains(tier) else { return nil }
        if let cached = cache[tier] { return cached }
        guard let image = NSImage(contentsOfFile: "\(directory)/tier-\(tier).png") else { return nil }
        cache[tier] = image
        return image
    }
}

/// Tavern tier beside a leaderboard portrait.
struct TierBadge: View {
    let tier: Int?
    let tile: CGFloat

    var body: some View {
        Text(verbatim: tier.flatMap { $0 > 0 ? "\($0)" : nil } ?? "?")
            .font(.system(size: tile * 0.13, weight: .heavy, design: .rounded))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: tile * 0.22, height: tile * 0.22)
            .background(Self.color(for: tier), in: RoundedRectangle(cornerRadius: tile * 0.04))
            .overlay(RoundedRectangle(cornerRadius: tile * 0.04)
                .strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
    }

    /// One color per tavern tier (1-6), following the familiar rarity ladder:
    /// grey, green, blue, purple, orange, red.
    static func color(for tier: Int?) -> Color {
        switch tier ?? 0 {
        case 1: Color(red: 0.78, green: 0.8, blue: 0.82)
        case 2: Color(red: 0.45, green: 0.85, blue: 0.4)
        case 3: Color(red: 0.35, green: 0.7, blue: 1.0)
        case 4: Color(red: 0.75, green: 0.5, blue: 1.0)
        case 5: Color(red: 1.0, green: 0.6, blue: 0.2)
        case 6...: Color(red: 1.0, green: 0.38, blue: 0.38)
        default: Color.white.opacity(0.35)
        }
    }
}
