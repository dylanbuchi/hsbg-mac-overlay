import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class OverlayModel: NSObject, ObservableObject {
    @Published private(set) var lobby = BattlegroundsLobby()
    @Published private(set) var status = "Waiting for Hearthstone Power.log…"
    /// Tags only make sense while the tavern is open: hidden in combat, menus and after the game.
    @Published private(set) var lobbySummary = ""
    @Published private(set) var showsTags = false
    @Published private(set) var nextOpponentPlace = 0
    @Published private(set) var turn = 0
    @Published private(set) var isInCombat = false
    @Published private(set) var isGameOver = false
    /// HSTracker's left panel in overlay coordinates; the NEXT OPPONENT card docks under it.
    @Published private(set) var trackerPanel: CGRect?
    /// An older leaderboard list (about a day back at most) for the card's rating change.
    @Published private(set) var ratingBaseline: RatingBaseline?
    /// Draw tavern tiers as the game's shield icons (from HSTracker) rather than colored numbers.
    @Published var showsTierIcons = UserDefaults.standard.object(forKey: "showsTierIcons") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsTierIcons, forKey: "showsTierIcons") }
    }
    /// Labels follow combat playback, so they stay correct during fights; hiding is a preference.
    var hidesDuringCombat = UserDefaults.standard.object(forKey: "hidesDuringCombat") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hidesDuringCombat, forKey: "hidesDuringCombat") }
    }

    /// Show the NEXT OPPONENT card during combat too (off by default).
    @Published var showsCardInCombat: Bool {
        didSet { preferences.showsCardInCombat = showsCardInCombat }
    }
    /// Demo mode: the model is fed by hand and never reads the game.
    private(set) var isDemo = false
    private let preferences: OverlayPreferences

    private var timer: Timer?
    private var ratingTask: Task<Void, Never>?
    private let poller = LogPoller()
    private var polling = false
    private var pollStartedAt = Date()
    private var latest = LogPoll()
    private var mirrorSnapshot: HearthMirrorLobbySnapshot?
    private var mirrorGameUUID: String?
    private var mirrorOrder: [String] = []
    /// Tribe counts read from game memory, by hero entity id; nil when off or not available.
    private var liveTribeCounts: [Int: [Int: Int]]?
    private var tribeGate = TribePollGate()
    private var tribeTask: Task<Void, Never>?
    private var tribeNote = ""
    private var tribeGame = 0
    private var ratings: [String: Int] = [:]
    private var ratingSource = ""
    private var ratingSchedule = RatingSchedule()
    private var leaderboardClient = LeaderboardClient(
        region: LeaderboardRegion(rawValue: UserDefaults.standard.string(forKey: "region") ?? "") ?? .eu,
        history: .standard
    )

    init(preferences: OverlayPreferences = OverlayPreferences()) {
        self.preferences = preferences
        showsCardInCombat = preferences.showsCardInCombat
        super.init()
    }

    /// Fixed state for the demo window; see `DemoMode`.
    func loadDemo(lobby: BattlegroundsLobby, nextOpponentPlace: Int, turn: Int, isInCombat: Bool, trackerPanel: CGRect?,
                  ratingBaseline: RatingBaseline? = nil) {
        isDemo = true
        self.lobby = lobby
        self.nextOpponentPlace = nextOpponentPlace
        self.turn = turn
        self.isInCombat = isInCombat
        self.isGameOver = false
        self.trackerPanel = trackerPanel
        self.ratingBaseline = ratingBaseline
        showsTags = !(hidesDuringCombat && isInCombat)
    }

    func start() {
        guard !isDemo else { return }
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
        tribeTask?.cancel()
        tribeTask = nil
    }

    func setRegion(_ region: LeaderboardRegion) {
        guard leaderboardClient.region != region else { return }
        leaderboardClient.region = region
        UserDefaults.standard.set(region.rawValue, forKey: "region")
        // A download for the old region must not land under the new one.
        ratingTask?.cancel()
        ratingTask = nil
        ratings.removeAll()
        ratingBaseline = nil
        ratingSource = ""
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
        if poll.isInCombat != isInCombat { isInCombat = poll.isInCombat }
        if poll.isGameOver != isGameOver { isGameOver = poll.isGameOver }
        if poll.turn != turn {
            turn = poll.turn
        }
        refreshRatingsIfNeeded()
        refreshTribesIfNeeded(poll)
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
            let mmr = ratingSchedule.failures > 0 && ratings.isEmpty ? "MMR offline, retrying"
                : "MMR \(leaderboardClient.region.rawValue)\(ratingSource.isEmpty ? "" : " via \(ratingSource)")"
            setStatus("Connected · \(lobby.players.count) players · \(mmr) · \(source)\(tribeNote)")
        } else {
            setStatus("Log connected · waiting for a Battlegrounds Solo match")
        }
    }

    func setTrackerPanel(_ frame: CGRect?) {
        if frame != trackerPanel { trackerPanel = frame }
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
        // Re-resolved on every publish: hero entities can be replaced during a game.
        LiveTribes.apply(liveTribeCounts, to: &updated.players)
        if updated != lobby { lobby = updated }
        let summary = LobbyStats.compute(players: updated.players)?.summary ?? ""
        if summary != lobbySummary { lobbySummary = summary }
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

    /// Reads the leaderboard tribe counts off the main thread, about every 3 s, only in a live Solo match.
    /// Any failure leaves the log-based tribes in place (after a few misses in a row) with a note in the status.
    private func refreshTribesIfNeeded(_ poll: LogPoll) {
        let enabled = SettingsModel.readsTribesFromMemory()
        if poll.gamesStarted != tribeGame {
            tribeGame = poll.gamesStarted
            dropLiveTribes()
        }
        guard enabled else {
            if liveTribeCounts != nil || !tribeNote.isEmpty { dropLiveTribes(); publishLobby() }
            return
        }
        guard tribeTask == nil,
              tribeGate.shouldRead(enabled: enabled, isBattlegrounds: poll.lobby.isBattlegrounds,
                                   isGameOver: poll.isGameOver, hasMirror: poll.mirror != nil, now: Date()) else {
            if poll.isGameOver || !poll.lobby.isBattlegrounds, liveTribeCounts != nil { dropLiveTribes(); publishLobby() }
            return
        }
        tribeGate.started(at: Date())
        let game = poll.gamesStarted
        tribeTask = Task { [weak self] in
            guard let self else { return }
            let result = await poller.tribes()
            tribeTask = nil
            guard !Task.isCancelled, game == tribeGame else { return }
            applyTribes(result)
        }
    }

    private func applyTribes(_ result: TribeReadResult) {
        switch result {
        case .counts(let counts):
            _ = tribeGate.finished(success: true)
            liveTribeCounts = counts
            tribeNote = " · live tribes"
        case .unavailable(let reason):
            if tribeGate.finished(success: false) { liveTribeCounts = nil }
            tribeNote = " · live tribes off: \(reason)"
        }
        publishLobby()
    }

    private func dropLiveTribes() {
        liveTribeCounts = nil
        tribeNote = ""
        tribeGate.reset()
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
                let result = try await leaderboardClient.fetchRatings()
                guard !Task.isCancelled else { return }
                ratings = result.ratings
                ratingBaseline = result.baseline
                ratingSource = result.label()
                // An old cached list is better than nothing, but the live sources are retried soon.
                if result.isCached {
                    ratingSchedule.failed(at: Date())
                } else {
                    ratingSchedule.succeeded(game: game, at: Date())
                }
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
