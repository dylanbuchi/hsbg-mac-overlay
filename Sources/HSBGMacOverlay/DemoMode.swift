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

    static var lobby: BattlegroundsLobby {
        func player(_ id: Int, _ name: String, place: Int, rating: Int?, record: (Int, Int), streak: Int, tier: Int,
                    tierTurn: Int, triples: Int? = nil, tribes: [String: Int] = [:], seen: Int? = nil,
                    board: (Int, Int)? = nil, local: Bool = false) -> BattlegroundsPlayer {
            var p = BattlegroundsPlayer(id: id, name: name, tavernTier: tier, placement: place, rating: rating)
            p.wins = record.0
            p.losses = record.1
            p.streak = streak
            p.tierReachedTurn = tierTurn
            p.triples = triples
            p.lastSeenTribes = tribes
            p.lastSeenTurn = seen
            p.lastBoardSize = board?.0
            p.lastBoardTier = board?.1
            p.isLocalPlayer = local
            return p
        }
        return BattlegroundsLobby(isBattlegrounds: true, players: [
            player(1, "Rossoneri", place: 1, rating: 12_691, record: (7, 1), streak: 5, tier: 5, tierTurn: 8, triples: 2,
                   tribes: ["DRAGON": 5, "BEAST": 3], seen: 9, board: (7, 5)),
            player(2, "KoreanKombo", place: 2, rating: 8_281, record: (4, 3), streak: -3, tier: 4, tierTurn: 7, triples: 1,
                   tribes: ["MECHANICAL": 4], seen: 5, board: (6, 4)),
            player(3, "Dakang", place: 3, rating: 8_037, record: (5, 2), streak: 2, tier: 4, tierTurn: 8),
            player(4, "Dredyx", place: 4, rating: 8_310, record: (5, 2), streak: 0, tier: 3, tierTurn: 6, local: true),
            player(5, "s1xp4ck", place: 5, rating: nil, record: (3, 4), streak: -2, tier: 3, tierTurn: 7,
                   tribes: ["UNDEAD": 4, "NAGA": 3], seen: 9, board: (5, 3)),
            player(6, "Fragonar", place: 6, rating: 9_012, record: (3, 4), streak: 1, tier: 2, tierTurn: 4, triples: 3),
            player(7, "Axernar", place: 7, rating: nil, record: (2, 5), streak: -4, tier: 2, tierTurn: 5),
            player(8, "Hatred", place: 8, rating: 8_044, record: (1, 6), streak: -1, tier: 1, tierTurn: 0),
        ])
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
    @State private var panel = DemoPanel.medium

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
            }
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
                Toggle("Card in combat", isOn: $model.showsCardInCombat)
                Toggle("Hide during combat", isOn: Binding(get: { model.hidesDuringCombat },
                                                           set: { model.hidesDuringCombat = $0; apply(nil) }))
            }
            .padding(10)
        }
    }

    @State private var lastSize = CGSize(width: 1280, height: 780)

    private func apply(_ size: CGSize?) {
        if let size { lastSize = size }
        model.loadDemo(lobby: DemoScenario.lobby, nextOpponentPlace: DemoScenario.nextOpponentPlace, turn: 10,
                       isInCombat: inCombat, trackerPanel: panel.frame(in: lastSize))
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
