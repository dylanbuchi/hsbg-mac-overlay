import SwiftUI

/// "How to Read the Overlay": every label drawn on the leaderboard, shown with
/// the overlay's own views and sample data, next to what it means.
struct LegendView: View {
    /// Large enough to read; the in-game labels scale the same way.
    private let tile: CGFloat = 110

    private var sample: BattlegroundsPlayer {
        var player = BattlegroundsPlayer(id: 1, name: "Player", tavernTier: 5, rating: 8500)
        player.wins = 10
        player.losses = 1
        player.streak = 4
        player.triples = 2
        player.tierReachedTurn = 9
        player.lastSeenTribes = ["DRAGON": 5]
        player.lastSeenTurn = 12
        return player
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How to Read the Overlay")
                    .font(.title2.bold())
                Text("Each portrait on the Battlegrounds leaderboard gets these labels. They appear once there is data for them.")
                    .foregroundStyle(.secondary)

                section("Name and MMR") {
                    row(Nameplate(player: sample, tile: tile).frame(width: tile * 0.9),
                        "Player name, with their rating from the public leaderboard underneath.")
                    row(Nameplate(player: BattlegroundsPlayer(id: 2, name: "Opponent"), tile: tile).frame(width: tile * 0.9),
                        "— means no public rating: usually below 8,000 (Blizzard only publishes the top of each region), sometimes a recent rename or a name shared by two leaderboard players.")
                }

                section("Tavern tier") {
                    row(tierExample, "Their tavern tier. With Tier Icons on, the game's shield (count the stars); off, a colored number: grey 1, green 2, blue 3, purple 4, orange 5, red 6.")
                }

                section("Record and streak") {
                    row(stats(wins: 10, losses: 1, streak: 4),
                        "10-1: rounds not lost, then rounds lost. A tie counts as not lost: nobody takes damage, so the log cannot tell it from a win.")
                    row(Image(systemName: "flame.fill").font(.title2)
                            .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)),
                        "Flame: 2 or more rounds in a row without losing, and how many.")
                }

                section("Second line") {
                    row(Text(verbatim: "🐉 5").font(.title3.bold()).foregroundStyle(.white),
                        "Their main tribe and how many minions of it, from their board the last time you fought them. A second tribe shows when they have 3 or more of it. Faded when that board is more than 2 turns old.")
                    row(Image(systemName: "sparkles").font(.title2).foregroundStyle(Color(red: 1, green: 0.84, blue: 0.35)),
                        "Triples they have made this game.")
                    row(Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(Color(white: 0.75)),
                        "The turn they reached their current tier. A low number means they levelled fast.")
                }

                section("Tribe icons") {
                    tribeLegend
                }

                section("Next opponent") {
                    row(Image(systemName: "arrow.right.square.fill").font(.title2).foregroundStyle(.red),
                        "The game pushes your next opponent's portrait out of the rail; their labels move with it.")
                }

                section("Menu bar options (BG icon)") {
                    bullet("Tier Icons", "shields or colored numbers.")
                    bullet("Hide During Combat", "hide labels while fights play. Labels follow the fight animation, so they stay correct if you show them.")
                    bullet("MMR Region", "EU, US or AP; use the region you play on.")
                }

                Text("Tribes count each minion's main tribe only, and appear only for players you have fought. Labels hide in menus and after the game.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 560, height: 640)
    }

    private static let tribeNames: [(key: String, name: String)] = [
        ("BEAST", "Beast"), ("DEMON", "Demon"), ("DRAGON", "Dragon"), ("ELEMENTAL", "Elemental"),
        ("MECHANICAL", "Mech"), ("MURLOC", "Murloc"), ("NAGA", "Naga"), ("PIRATE", "Pirate"),
        ("QUILBOAR", "Quilboar"), ("UNDEAD", "Undead"), ("ABERRATION", "Aberration"),
        ("ALL", "Amalgam (every tribe)"),
    ]

    private var tribeLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Self.tribeNames, id: \.key) { tribe in
                HStack(spacing: 8) {
                    Text(verbatim: PlayerStats.tribeIcons[tribe.key] ?? "❔")
                        .font(.title3)
                    Text(tribe.name)
                }
            }
        }
    }

    @ViewBuilder
    private var tierExample: some View {
        HStack(spacing: 12) {
            if let icon = TierIcons.image(for: 5) {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(height: 34)
            }
            TierBadge(tier: 5, tile: tile)
        }
    }

    private func stats(wins: Int, losses: Int, streak: Int) -> some View {
        var player = sample
        player.wins = wins
        player.losses = losses
        player.streak = streak
        player.triples = nil
        player.tierReachedTurn = nil
        player.lastSeenTribes = [:]
        return PlayerStats(player: player, tile: tile, currentTurn: 12)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func row(_ visual: some View, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                // A dark swatch, like the game board behind the labels.
                RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.18, green: 0.14, blue: 0.12))
                visual
            }
            .frame(width: 130, height: 54)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ title: String, _ text: String) -> some View {
        (Text(title).bold() + Text(": \(text)"))
            .fixedSize(horizontal: false, vertical: true)
    }
}
