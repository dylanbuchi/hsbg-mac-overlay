import SwiftUI

/// "How to Read the Overlay": every label drawn on the leaderboard, shown with
/// the overlay's own views and sample data, next to what it means.
struct LegendView: View {
    /// Large enough to read; the in-game labels scale the same way.
    private let tile: CGFloat = 110
    private var art: CGFloat { tile * 0.9 }

    private var sample: BattlegroundsPlayer {
        var player = BattlegroundsPlayer(id: 1, name: "Player", tavernTier: 5, rating: 8500)
        player.wins = 10
        player.losses = 1
        player.streak = 4
        player.triples = 2
        player.tierReachedTurn = 9
        player.lastSeenTribes = ["DRAGON": 5]
        player.lastSeenTurn = 12
        player.lastBoardSize = 7
        player.lastBoardTier = 5
        return player
    }

    private func label(_ player: BattlegroundsPlayer, leader: Bool = false) -> some View {
        EdgeInkLabel(content: EdgeInkContent(player: player, isLeader: leader), width: art)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How to Read the Overlay")
                    .font(.title2.bold())
                Text("Each portrait on the Battlegrounds leaderboard gets a small label at the top. It appears once there is data for it.")
                    .foregroundStyle(.secondary)

                section("Name and MMR") {
                    row(label(sample),
                        "Player name, then their rating from the public leaderboard (gold) and their record. Here: 8,500 MMR, 10 rounds not lost, 1 lost.")
                    row(label(BattlegroundsPlayer(id: 2, name: "Opponent")),
                        "No MMR under the name means no public rating: usually below 8,000 (Blizzard only publishes the top of each region), sometimes a recent rename or a name shared by two leaderboard players.")
                    row(label(sample, leader: true),
                        "The brightest, bolder gold MMR is the highest rating in the lobby (when at least two players are listed and no one ties for first).")
                    row(label(localSample),
                        "A small blue dot after the name is you.")
                }

                section("Record and streak") {
                    row(label(sample),
                        "10-1: rounds not lost, then rounds lost. A tie counts as not lost: nobody takes damage, so the log cannot tell it from a win.")
                    row(label(lossSample),
                        "▲ 4: 2 or more rounds in a row without losing (amber, pointing up). ▼ 3: 2 or more rounds lost in a row (blue, pointing down). The arrow says which, not only the colour.")
                    row(label(sample),
                        "A small gold disc and a number, under the MMR: triples they have made this game. Shown once they have at least one.")
                    bullet("Small windows", "the label drops the record first, then the streak, so the name and MMR always stay readable.")
                }

                section("Tavern tier") {
                    row(tierExample, "Their tavern tier. With Tier Icons on, the game's shield, one star per tier; off, a colored number: grey 1, green 2, blue 3, purple 4, orange 5, red 6.")
                }

                section("Tribes") {
                    row(TribeBadges(tribes: [TribeCount(tribe: "DRAGON", count: 5), TribeCount(tribe: "BEAST", count: 3)],
                                    size: 16, isStale: false),
                        "Under the tier shield: their main tribe and how many minions of it. With live tribes on (Settings) this is the game's own leaderboard hover data, read from turn 1 and refreshed every few seconds; otherwise it comes from their board the last time you fought them (a second tribe shows at 3 or more, faded when more than 2 turns old). The NEXT OPPONENT card labels its top three tribes (2 or more minions each) \"live\" or \"seen turn N\".")
                    tribeLegend
                }

                section("Next opponent") {
                    Text("During the shop phase a card for that player sits on the left of the window, under HSTracker's panel (or lower left if HSTracker is not found). It shows their name, MMR and rank among listed players, record and streak, the tier they are at and the turn they reached it, their last board (a row of their minions with the turn you saw it; Not fought yet before you meet; point at a minion to see it larger), their health and armor with the damage of their last combat, their triples once they have one (with the turns they were seen, the last three), their lesser and greater trinkets at the top right once picked (point at one to see it larger), and, after you have fought them, the latest fight each way. The MMR can carry a change since an older leaderboard snapshot; with no public rating there is no MMR line. A dash means unknown. After a reconnect, turns the overlay did not see are left out. It hides during combat, after the last fight and when there is no next opponent.")
                        .fixedSize(horizontal: false, vertical: true)
                    NextOpponentCard(content: NextOpponentContent(player: sample, lobby: [sample], currentTurn: 12),
                                     layout: NextOpponentLayout(canvas: CGSize(width: 1280, height: 1000), trackerPanel: nil))
                        .padding(.vertical, 4)
                    Text("In Dark Gifts lobbies, a small box under the Dark Discovery button counts the Dark Discoveries you can still use this game (3 per game). It hides once all are used.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("Tavern list") {
                    Text("In the shop, a strip of tiers 1 to 6 sits at the top centre. Point at a tier to see what it can offer in this lobby: a column per tribe, then amalgams, minions with no tribe and the tier's spells (with their gold cost). Tags: BC Battlecry, DR Deathrattle, DS Divine Shield, T Taunt, EoT End of turn, R Reborn. Without the lobby's tribes from the game reader, every tribe is listed. Card data from HearthstoneJSON.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                section("Menu bar options (BG icon)") {
                    bullet("Tier Icons", "shields or colored numbers.")
                    bullet("Show Overlay During Combat", "keep labels on while fights play (off by default). Labels follow the fight animation, so they stay correct if you show them.")
                    bullet("MMR Region", "EU, US or AP; use the region you play on.")
                    bullet("Show Next Opponent During Combat", "keep the NEXT OPPONENT card on while fights play (off by default).")
                    bullet("Moving the card", "point at the card: drag the gold grip at the top to move it, the gold corner to resize it. Saved for this window shape. Move Card… does the same from the menu; Reset Card Position goes back to automatic.")
                    bullet("Player names", "are read from the game by the overlay itself (read only; macOS asks for your password the first time). Without them the labels still show tiers, records and streaks, but no names or MMR; the first menu line says why.")
                }

                Text("Live counts can exceed a board's size because two-tribe minions count for both tribes (Amalgams for every tribe); read them as “most of”. Without live data, tribes appear only for players you have fought. Labels hide in menus and after the game.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 560, height: 640)
    }

    private var localSample: BattlegroundsPlayer {
        var player = sample
        player.isLocalPlayer = true
        player.streak = 0
        return player
    }

    private var lossSample: BattlegroundsPlayer {
        var player = sample
        player.wins = 4
        player.losses = 7
        player.streak = -3
        return player
    }

    private static let tribeKeys = ["BEAST", "DEMON", "DRAGON", "ELEMENTAL", "MECHANICAL", "MURLOC",
                                    "NAGA", "PIRATE", "QUILBOAR", "UNDEAD", "ABERRATION", "ALL"]

    private var tribeLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Self.tribeKeys, id: \.self) { key in
                HStack(spacing: 8) {
                    TribeIcon(tribe: key, size: 20)
                    Text(key == "ALL" ? "Amalgam (every tribe)" : TribeNames.plural(key))
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
            .frame(width: 130, height: 62)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ title: String, _ text: String) -> some View {
        (Text(title).bold() + Text(": \(text)"))
            .fixedSize(horizontal: false, vertical: true)
    }
}
