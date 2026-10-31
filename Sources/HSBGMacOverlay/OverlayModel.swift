import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class OverlayModel: NSObject, ObservableObject {
    @Published private(set) var lobby = BattlegroundsLobby()
    @Published private(set) var status = "Waiting for Hearthstone Power.log…"
    /// Tags only make sense while the tavern is open: hidden in combat, menus and after the game.
    @Published private(set) var showsTags = false
    @Published private(set) var nextOpponentPlace = 0
    @Published private(set) var turn = 0
    /// Draw tavern tiers as the game's shield icons (from HSTracker) rather than colored numbers.
    @Published var showsTierIcons = UserDefaults.standard.object(forKey: "showsTierIcons") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsTierIcons, forKey: "showsTierIcons") }
    }
    /// Labels follow combat playback, so they stay correct during fights; hiding is a preference.
    var hidesDuringCombat = UserDefaults.standard.object(forKey: "hidesDuringCombat") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hidesDuringCombat, forKey: "hidesDuringCombat") }
    }

    private var timer: Timer?
    private var ratingTask: Task<Void, Never>?
    private let poller = LogPoller()
    private var polling = false
    private var pollStartedAt = Date()
    private var latest = LogPoll()
    private var mirrorSnapshot: HearthMirrorLobbySnapshot?
    private var mirrorGameUUID: String?
    private var mirrorOrder: [String] = []
    private var ratings: [String: Int] = [:]
    private var ratingSchedule = RatingSchedule()
    private var leaderboardClient = LeaderboardClient(
        region: LeaderboardRegion(rawValue: UserDefaults.standard.string(forKey: "region") ?? "") ?? .eu
    )

    func start() {
        guard timer == nil else { return }
        refresh()
        // .common keeps it firing while a menu is open or a window is being dragged.
        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(refreshTimerFired),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ratingTask?.cancel()
        ratingTask = nil
    }

    func setRegion(_ region: LeaderboardRegion) {
        guard leaderboardClient.region != region else { return }
        leaderboardClient.region = region
        UserDefaults.standard.set(region.rawValue, forKey: "region")
        // A download for the old region must not land under the new one.
        ratingTask?.cancel()
        ratingTask = nil
        ratings.removeAll()
        ratingSchedule.reset()
        publishLobby()
    }

    var region: LeaderboardRegion {
        leaderboardClient.region
    }

    @objc private func refreshTimerFired() {
        refresh()
    }

    private func refresh() {
        // Reading and parsing happen off the main thread; a slow pass just skips ticks.
        guard !polling else {
            if Date().timeIntervalSince(pollStartedAt) > 30 {
                setStatus("Reading the game stalled · restart the overlay if this stays")
            }
            return
        }
        polling = true
        pollStartedAt = Date()
        Task {
            let poll = await poller.poll()
            polling = false
            apply(poll)
            // Catching up on a big log: keep going without waiting for the next tick.
            if poll.outcome == .ok, poll.bytesRemaining > 0 { refresh() }
        }
    }

    private func apply(_ poll: LogPoll) {
        switch poll.outcome {
        case .noLog:
            setStatus("No Power.log yet: enable Power logging (see README) and restart Hearthstone")
            return
        case .readFailed:
            if showsTags { showsTags = false }
            setStatus("Could not read Power.log · v\(AppInfo.version)")
            return
        case .ok:
            break
        }

        latest = poll
        mirrorSnapshot = poll.mirror
        if mirrorSnapshot == nil {
            mirrorGameUUID = nil
            mirrorOrder.removeAll()
        }
        publishLobby(parsed: poll.lobby)
        let shows = lobby.isBattlegrounds && !poll.isGameOver
            && !(hidesDuringCombat && poll.isInCombat)
        if shows != showsTags { showsTags = shows }
        if poll.nextOpponentPlace != nextOpponentPlace {
            nextOpponentPlace = poll.nextOpponentPlace
        }
        if poll.turn != turn {
            turn = poll.turn
        }
        refreshRatingsIfNeeded()
        if poll.bytesRemaining > 0 {
            let done = Int(Double(poll.fileSize - poll.bytesRemaining) / Double(max(poll.fileSize, 1)) * 100)
            setStatus("Reading Power.log… \(done)%")
            return
        }
        let source: String
        switch poll.mirrorError {
        case "live": source = "names from HSTracker"
        // The lobby only exists once a match is found.
        case "HearthMirror lobby unavailable", "HearthMirror returned no players": source = "waiting for lobby names"
        default: source = "no names: \(poll.mirrorError) · v\(AppInfo.version)"
        }
        if poll.isDuos {
            setStatus("Duos is not supported yet")
        } else if poll.isGameOver {
            setStatus("Game over · waiting for the next match")
        } else if lobby.isBattlegrounds {
            let mmr = ratingSchedule.failures > 0 ? "MMR offline, retrying" : "MMR \(leaderboardClient.region.rawValue)"
            setStatus("Connected · \(lobby.players.count) players · \(mmr) · \(source)")
        } else {
            setStatus("Log connected · waiting for a Battlegrounds Solo match")
        }
    }

    private func setStatus(_ text: String) {
        if status != text { status = text }
    }

    private func publishLobby(parsed: BattlegroundsLobby? = nil) {
        var updated = parsed ?? latest.lobby
        if let mirrorSnapshot {
            updated = merge(mirrorSnapshot, with: updated)
        }
        for index in updated.players.indices {
            updated.players[index].rating = ratings[LeaderboardName.normalize(updated.players[index].name)]
        }
        if updated != lobby { lobby = updated }
    }

    private func merge(_ mirror: HearthMirrorLobbySnapshot, with parsed: BattlegroundsLobby) -> BattlegroundsLobby {
        let identities = mirror.players.map(LobbyIdentity.identity(for:))
        if mirrorGameUUID != mirror.gameUUID || LobbyIdentity.shouldResetOrder(existing: mirrorOrder, incoming: identities) {
            mirrorGameUUID = mirror.gameUUID
            mirrorOrder = identities
        } else {
            mirrorOrder = StableLobbyOrder.update(existing: mirrorOrder, incoming: identities)
        }

        // Identities can repeat while the lobby is still loading (e.g. account 0:0).
        let mirrorByIdentity = Dictionary(mirror.players.map { (LobbyIdentity.identity(for: $0), $0) },
                                          uniquingKeysWith: { first, _ in first })
        let orderedMirrorPlayers = mirrorOrder.compactMap { identity in
            mirrorByIdentity[identity].map { (identity: identity, player: $0) }
        }
        let players = LeaderboardMerge.players(
            mirrorPlayers: orderedMirrorPlayers,
            parsed: parsed.players,
            localPlayerName: mirror.localPlayerName,
            fallbackID: LobbyIdentity.fallbackID
        )
        // The mirror also has a lobby in Duos; the log decides whether this is a Solo match.
        return BattlegroundsLobby(isBattlegrounds: parsed.isBattlegrounds, players: players)
    }

    private func refreshRatingsIfNeeded() {
        let game = latest.gamesStarted
        guard lobby.isBattlegrounds,
              !lobby.players.filter({ !$0.isLocalPlayer && !$0.name.isEmpty }).isEmpty,
              ratingTask == nil,
              ratingSchedule.shouldFetch(now: Date(), currentGame: game) else { return }

        ratingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let freshRatings = try await leaderboardClient.fetchRatings()
                guard !Task.isCancelled else { return }
                ratings = freshRatings
                ratingSchedule.succeeded(game: game, at: Date())
                publishLobby()
            } catch {
                // Local log data remains useful when the optional lookup is offline.
                guard !Task.isCancelled else { return }
                ratingSchedule.failed(at: Date())
            }
            ratingTask = nil
        }
    }
}
