import AppKit
import SwiftUI

/// Hidden demo mode for checking the interface without playing: `HSBGMacOverlay --demo` (or the
/// environment variable HSBG_DEMO=1). A plain dark window shows the real overlay views over a
/// made-up lobby, with a fake panel standing in for HSTracker's. The Power.log parser is not
/// involved: the lobby is built by hand (`DemoScenario`). Not listed in any menu.
enum DemoMode {
    static func isRequested(arguments: [String] = CommandLine.arguments,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        arguments.contains("--demo") || environment["HSBG_DEMO"] == "1"
    }
}

enum DemoScenario {
    /// Eight players, you in 4th place, the next opponent in 2nd: one unlisted, one on a loss
    /// streak, one with triples and a stale board, one nobody has fought yet.
    static let nextOpponentPlace = 2

    /// The made-up next opponent, shown while the card is being placed outside a game.
    static var nextOpponent: BattlegroundsPlayer? {
        lobby(atGameStart: false).players.first { $0.placement == nextOpponentPlace }
    }

    /// The lobby with everything the log would have taught by turn 10, or as it looks at the very
    /// start of a game (no fights, boards, triples or health lost yet).
    static func lobby(atGameStart: Bool) -> BattlegroundsLobby {
        var lobby = fullLobby
        guard atGameStart else { return lobby }
        for index in lobby.players.indices {
            // Live counts exist from turn 1 but are small then.
            lobby.players[index].liveTribes = lobby.players[index].liveTribes.map { $0.mapValues { min($0, 2) } }
            lobby.players[index].lastSeenTribes = [:]
            lobby.players[index].lastSeenTurn = nil
            lobby.players[index].lastBoardSize = nil
            lobby.players[index].lastBoardTier = nil
            lobby.players[index].lastBoardMinions = []
            lobby.players[index].triples = nil
            lobby.players[index].tripleTurns = []
            lobby.players[index].damageTaken = 0
            lobby.players[index].armor = 0
            lobby.players[index].lastCombatDamage = nil
            lobby.players[index].fightsWithYou = []
            lobby.players[index].lesserTrinketID = nil
            lobby.players[index].greaterTrinketID = nil
        }
        return lobby
    }

    /// A leaderboard list from six hours earlier: Ironquill up 45, Gloamfin down 89, Marrowmoss
    /// not listed back then (so no change is shown for them).
    static func baseline(now: Date = Date()) -> RatingBaseline {
        RatingBaseline(ratings: ["Ironquill": 12_455, "Gloamfin": 8_389, "Player": 8_100, "Copperkettle": 9_000, "Saltglass": 8_050],
                       savedAt: now.addingTimeInterval(-6 * 3600))
    }

    private static var fullLobby: BattlegroundsLobby {
        func player(_ id: Int, _ name: String, place: Int, rating: Int?, record: (Int, Int), streak: Int, tier: Int,
                    tierTurn: Int, triples: Int? = nil, tribes: [String: Int] = [:], seen: Int? = nil,
                    board: (Int, Int)? = nil, minions: [String]? = nil, local: Bool = false) -> BattlegroundsPlayer {
            var p = BattlegroundsPlayer(id: id, name: name, tavernTier: tier, placement: place, rating: rating)
            p.wins = record.0
            p.losses = record.1
            p.streak = streak
            p.tierReachedTurn = tierTurn
            p.triples = triples
        p.tripleTurns = (0..<(triples ?? 0)).map { 6 + 2 * $0 }
            p.lastSeenTribes = tribes
            p.lastSeenTurn = seen
            p.lastBoardSize = board?.0
            p.lastBoardTier = board?.1
            if let minions { p.lastBoardMinions = minions.map { BoardMinion(cardID: "", name: $0, isGolden: false) } }
            p.isLocalPlayer = local
            return p
        }
        var lobby = BattlegroundsLobby(isBattlegrounds: true, players: [
            player(1, "Ironquill", place: 1, rating: 12_500, record: (7, 1), streak: 5, tier: 5, tierTurn: 8, triples: 2,
                   tribes: ["DRAGON": 5, "BEAST": 3], seen: 9, board: (7, 5)),
            player(2, "Gloamfin", place: 2, rating: 8_300, record: (4, 3), streak: -3, tier: 4, tierTurn: 7, triples: 1,
                   tribes: ["MECHANICAL": 4], seen: 7, board: (6, 4),
                   minions: ["Micro Machine", "Annoy-o-Module", "Mecharoo", "Replicating Menace", "Sellemental", "Southsea Captain"]),
            player(3, "Marrowmoss", place: 3, rating: 8_000, record: (5, 2), streak: 2, tier: 4, tierTurn: 8),
            player(4, "Player", place: 4, rating: 8_100, record: (5, 2), streak: 0, tier: 3, tierTurn: 6, local: true),
            player(5, "Tidebreaker", place: 5, rating: nil, record: (3, 4), streak: -2, tier: 3, tierTurn: 7,
                   tribes: ["UNDEAD": 4, "NAGA": 3], seen: 9, board: (5, 3)),
            player(6, "Copperkettle", place: 6, rating: 9_000, record: (3, 4), streak: 1, tier: 2, tierTurn: 4, triples: 3),
            player(7, "Thistledown", place: 7, rating: nil, record: (2, 5), streak: -4, tier: 2, tierTurn: 5),
            player(8, "Saltglass", place: 8, rating: 8_050, record: (1, 6), streak: -1, tier: 1, tierTurn: 0),
        ])
        for index in lobby.players.indices {
            lobby.players[index].health = 40
        }
        // Live counts as the game's hover would show them (Amalgams already added to each tribe).
        let live: [Int: [String: Int]] = [
            0: ["DRAGON": 6, "BEAST": 3, "MECHANICAL": 1], 1: ["MECHANICAL": 5, "ELEMENTAL": 3, "PIRATE": 2],
            2: ["MURLOC": 4, "NAGA": 2], 4: ["UNDEAD": 5, "NAGA": 4, "DEMON": 1],
            5: ["PIRATE": 3, "BEAST": 1], 6: ["DEMON": 2],
        ]
        for (index, tribes) in live { lobby.players[index].liveTribes = tribes }
        // The next opponent: 23 health left, 4 armor, hurt for 9 in the last fight, and the two of
        // you have beaten each other once.
        lobby.players[1].damageTaken = 17
        lobby.players[1].armor = 4
        lobby.players[1].lastCombatDamage = 9
        // Real trinket ids (Lens Case, and a greater one), so the demo shows the art from hsbg.cards.
        lobby.players[1].lesserTrinketID = 130835
        lobby.players[1].greaterTrinketID = 131303
        lobby.players[1].fightsWithYou = [FightWithYou(youWon: false, turn: 5, damage: 9),
                                          FightWithYou(youWon: true, turn: 9, damage: 12)]
        return lobby
    }
}

/// Fake HSTracker panel heights as a fraction of the window height (a "Latest Games" list with
/// 4, 6 or 10 rows), or none (the overlay then uses its fixed fallback position).
enum DemoPanel: String, CaseIterable, Identifiable {
    case none = "No panel", short = "4 rows", medium = "6 rows", tall = "10 rows"
    var id: String { rawValue }

    func frame(in canvas: CGSize) -> CGRect? {
        let height: CGFloat
        switch self {
        case .none: return nil
        case .short: height = 0.42
        case .medium: height = 0.47
        case .tall: height = 0.58
        }
        return CGRect(x: 0, y: canvas.height * 0.035, width: canvas.height * 0.176, height: canvas.height * height)
    }
}

struct DemoRoot: View {
    @ObservedObject var model: OverlayModel
    @State private var inCombat = false
    @State private var panel = DemoPanel.none
    @State private var atGameStart = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color(red: 0.07, green: 0.06, blue: 0.1)
                    portraitFrames(geometry.size)
                    if let frame = panel.frame(in: geometry.size) {
                        Rectangle().fill(Color.gray.opacity(0.35))
                            .overlay(Text("fake HSTracker panel").foregroundStyle(.white.opacity(0.6)))
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                    InGameOverlayView(model: model)
                }
                .onAppear { apply(geometry.size) }
                .onChange(of: geometry.size) { apply($0) }
                .onChange(of: inCombat) { _ in apply(geometry.size) }
                .onChange(of: panel) { _ in apply(geometry.size) }
                .onChange(of: atGameStart) { _ in apply(geometry.size) }
            }
            // A 16:9 game window like the real one, top-left in the demo window: the leaderboard's
            // width follows the aspect ratio, and with it the room the card gets.
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 20) {
                Picker("Phase", selection: $inCombat) {
                    Text("Shop").tag(false)
                    Text("Combat").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 200)
                Picker("Panel", selection: $panel) {
                    ForEach(DemoPanel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 340)
                Picker("Data", selection: $atGameStart) {
                    Text("Turn 10").tag(false)
                    Text("Game start").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 200)
                Toggle("Card in combat", isOn: $model.showsCardInCombat)
                Toggle("Hide during combat", isOn: Binding(get: { model.hidesDuringCombat },
                                                           set: { model.hidesDuringCombat = $0; apply(nil) }))
                Button("Move Card…") { NotificationCenter.default.post(name: .moveNextOpponentCard, object: nil) }
                Button("Reset Card") { NotificationCenter.default.post(name: .resetNextOpponentCard, object: nil) }
            }
            .padding(10)
        }
    }

    @State private var lastSize = CGSize(width: 1280, height: 780)

    private func apply(_ size: CGSize?) {
        if let size { lastSize = size }
        model.loadDemo(lobby: DemoScenario.lobby(atGameStart: atGameStart), nextOpponentPlace: DemoScenario.nextOpponentPlace,
                       turn: atGameStart ? 1 : 10, isInCombat: inCombat, trackerPanel: panel.frame(in: lastSize),
                       ratingBaseline: atGameStart ? nil : DemoScenario.baseline(),
                       darkGiftUsesLeft: atGameStart ? nil : 2)
    }

    private func portraitFrames(_ size: CGSize) -> some View {
        let layout = LeaderboardLayout(canvasSize: size, nextOpponentPlace: DemoScenario.nextOpponentPlace)
        let tile = layout.tileHeight
        return ZStack(alignment: .topLeading) {
            ForEach(0..<LeaderboardLayout.slots, id: \.self) { slot in
                RoundedRectangle(cornerRadius: tile * 0.06)
                    .fill(Color(red: 0.35, green: 0.3, blue: 0.42))
                    .frame(width: tile * 0.74, height: tile * 0.85)
                    .offset(x: layout.left(for: slot) + tile * 0.13, y: layout.top(for: slot) + tile * 0.1)
            }
        }
    }
}
