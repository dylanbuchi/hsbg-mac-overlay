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
                let leaderID = LobbyStats.leaderID(in: model.lobby.players)
                let nextOpponent = NextOpponentRules.opponent(
                    players: model.lobby.players, nextPlace: model.nextOpponentPlace,
                    isBattlegrounds: model.lobby.isBattlegrounds, isInCombat: model.isInCombat,
                    isGameOver: model.isGameOver, showsInCombat: model.showsCardInCombat)
                ZStack(alignment: .topLeading) {
                ForEach(Array(model.lobby.players.enumerated()), id: \.element.id) { index, player in
                    let slot = slots[index]
                    if (0..<LeaderboardLayout.slots).contains(slot) {
                        let left = layout.left(for: slot)
                        let top = layout.top(for: slot)
                        // No name means the lobby has not been read yet: show the tier alone.
                        if !player.name.isEmpty {
                            let artWidth = tile * 0.74
                            EdgeInkLabel(content: EdgeInkContent(player: player, isLeader: player.id == leaderID),
                                         width: artWidth)
                                .offset(x: left + tile * 0.13, y: top + tile * 0.1)
                        }
                        let tribes = TribeSummary.main(from: player.lastSeenTribes)
                        if !tribes.isEmpty {
                            TribeBadges(tribes: tribes, size: max(tile * 0.17, 14),
                                        isStale: TribeSummary.isStale(lastSeenTurn: player.lastSeenTurn, currentTurn: model.turn))
                                .offset(x: left + tile * 0.9, y: top + tile * 0.4)
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
                    }
                }
                }
                .opacity(model.showsTags ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: model.showsTags)
                if let nextOpponent,
                   case let dock = NextOpponentLayout(canvas: geometry.size, trackerPanel: model.trackerPanel,
                                                      rightLimit: layout.labelsLeftEdge),
                   dock.fits {
                    NextOpponentCard(content: NextOpponentContent(player: nextOpponent, lobby: model.lobby.players,
                                                                  currentTurn: model.turn),
                                     layout: dock)
                        .offset(x: dock.origin.x, y: dock.origin.y)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear { if !model.isDemo { model.start() } }
        .onDisappear { model.stop() }
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
