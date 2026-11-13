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
    /// Dark Discoveries you have left this game; nil outside Dark Gifts lobbies.
    @Published private(set) var darkGiftUsesLeft: Int?
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
    /// The overlay canvas, reported by the view, so the status can say why the card is not drawn.
    var canvasSize: CGSize = .zero
    /// Where the user put the NEXT OPPONENT card; empty for automatic docking.
    @Published private(set) var cardPlacements = CardPlacements()
    /// While true the card is shown (with demo content when no opponent is known) and can be dragged.
    @Published var isEditingCard = false
    /// The card's frame in game-window coordinates as last drawn; nil when it is not drawn.
    var cardFrame: CGRect?
    /// True while a hover handle is being dragged; the minion zoom stays out of the way.
    var isDraggingCard = false

    /// `persist: false` while a drag is in progress; the drop writes it to the defaults.
    func saveCardPlacement(_ placement: CardPlacement, canvas: CGSize, persist: Bool = true) {
        cardPlacements.save(placement, for: canvas)
        if persist { preferences.cardPlacements = cardPlacements }
    }

    func resetCardPlacement() {
        cardPlacements = CardPlacements()
        preferences.cardPlacements = cardPlacements
    }

    /// Where the card's minion thumbnails are (game-window coordinates); empty when the card or its board is not drawn.
    var minionTiles = MinionTiles.empty

    /// The tavern list for this game, one sheet per tier; built off the main thread once per game (again when
    /// the lobby's tribes or a fresher pool arrive). Empty until the first build.
    @Published private(set) var tavernSheets: [TavernSheet] = []
    /// The tier strip's tiles in game-window coordinates, as last drawn; empty when hidden.
    var tavernStripTiles: [TavernStripTile] = []
    /// True when the sheets follow the lobby's own tribes, false while they show every tribe.
    private(set) var tavernUsesLobbyTribes = false
    private let tavernPool = TavernPoolStore()
    private var tavernGame = -1
    private var tavernTask: Task<Void, Never>?
    private var lobbyTribes: Set<String>?
    private var lobbyRaceTries = 0
    private var lobbyRaceTask: Task<Void, Never>?
    private var lobbyRaceReadAt: Date?

    /// The strip shows in the shop phase of a Solo match, when the setting is on and the list is ready.
    var showsTavernStrip: Bool {
        !tavernSheets.isEmpty && lobby.isBattlegrounds && showsTags && !isInCombat && !isGameOver
            && SettingsModel.showsTavernList()
    }

    private var timer: Timer?
    /// Name join problems go to ~/Library/Logs/HSBGMacOverlay; tests and the demo leave it nil.
    var diagnostics: DiagnosticsLog?
    private var ratingTask: Task<Void, Never>?
    private let poller = LogPoller()
    private var polling = false
    private var pollStartedAt = Date()
    private var latest = LogPoll()
    private var mirrorSnapshot: LobbySnapshot?
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
        cardPlacements = preferences.cardPlacements
        super.init()
    }

    /// Fixed state for the demo window; see `DemoMode`.
    func loadDemo(lobby: BattlegroundsLobby, nextOpponentPlace: Int, turn: Int, isInCombat: Bool, trackerPanel: CGRect?,
                  ratingBaseline: RatingBaseline? = nil, darkGiftUsesLeft: Int? = nil) {
        isDemo = true
        self.darkGiftUsesLeft = darkGiftUsesLeft
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
        tavernTask?.cancel()
        tavernTask = nil
        lobbyRaceTask?.cancel()
        lobbyRaceTask = nil
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
        case .noMatchYet:
            clearMatch()
            setStatus("Log connected · waiting for a Battlegrounds Solo match")
            return
        case .noLog:
            clearMatch()
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
        if poll.darkGiftUsesLeft != darkGiftUsesLeft { darkGiftUsesLeft = poll.darkGiftUsesLeft }
        refreshRatingsIfNeeded()
        refreshTribesIfNeeded(poll)
        refreshTavernIfNeeded(poll)
        if poll.bytesRemaining > 0 {
            let done = Int(Double(poll.fileSize - poll.bytesRemaining) / Double(max(poll.fileSize, 1)) * 100)
            setStatus("Reading Power.log… \(done)%")
            return
        }
        let source: String
        switch poll.mirrorError {
        case "live": source = "names live"
        // The lobby only exists once a match is found.
        case GameReaderBridge.waitingMessage: source = GameReaderBridge.waitingMessage
        default: source = "no player names: \(poll.mirrorError) · v\(AppInfo.version)"
        }
        if poll.isDuos {
            setStatus("Duos is not supported yet")
        } else if poll.isGameOver {
            setStatus("Game over · waiting for the next match")
        } else if lobby.isBattlegrounds {
            let mmr = ratingSchedule.failures > 0 && ratings.isEmpty ? "MMR offline, retrying"
                : "MMR \(leaderboardClient.region.rawValue)\(ratingSource.isEmpty ? "" : " via \(ratingSource)")"
            setStatus("Connected · \(lobby.players.count) players · \(mmr) · \(source)\(tribeNote)\(tavernNote)\(cardNote)")
        } else {
            setStatus("Log connected · waiting for a Battlegrounds Solo match")
        }
    }

    /// " · card hidden: why" while the recap phase should show the card but it cannot be drawn, or a word on
    /// the user's own spot.
    private var cardNote: String {
        guard lobby.isBattlegrounds, !isGameOver, !isInCombat || showsCardInCombat else { return "" }
        if let custom = cardPlacements.placement(for: canvasSize), canvasSize.width > 0 {
            let fits = NextOpponentLayout.custom(custom, canvas: canvasSize, hasStatusRow: true, hasVersusRow: false,
                                                 hasTribesRow: false) != nil
            if fits { return " · card: your spot" }
            let auto = NextOpponentRules.hiddenReason(
                players: lobby.players, nextPlace: nextOpponentPlace, canvas: canvasSize, trackerPanel: trackerPanel,
                labelsLeftEdge: LeaderboardLayout(canvasSize: canvasSize, nextOpponentPlace: nextOpponentPlace).labelsLeftEdge,
                turn: turn, baseline: ratingBaseline)
            return " · card: your spot does not fit this window, using automatic" + (auto.map { " (hidden: \($0))" } ?? "")
        }
        guard let reason = NextOpponentRules.hiddenReason(
            players: lobby.players, nextPlace: nextOpponentPlace, canvas: canvasSize, trackerPanel: trackerPanel,
            labelsLeftEdge: LeaderboardLayout(canvasSize: canvasSize, nextOpponentPlace: nextOpponentPlace).labelsLeftEdge,
            turn: turn, baseline: ratingBaseline) else { return "" }
        return " · card hidden: \(reason)"
    }

    func setTrackerPanel(_ frame: CGRect?) {
        if frame != trackerPanel { trackerPanel = frame }
    }

    private func setStatus(_ text: String) {
        if status != text { status = text }
    }

    /// No current game (no log for this session yet): nothing from an older match stays on screen.
    private func clearMatch() {
        if showsTags { showsTags = false }
        if lobby != BattlegroundsLobby() { lobby = BattlegroundsLobby() }
        if nextOpponentPlace != 0 { nextOpponentPlace = 0 }
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

    private func merge(_ mirror: LobbySnapshot, with parsed: BattlegroundsLobby) -> BattlegroundsLobby {
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
        let outcome = LeaderboardMerge.merge(
            mirrorPlayers: orderedMirrorPlayers,
            parsed: parsed.players,
            localPlayerName: mirror.localPlayerName,
            fallbackID: LobbyIdentity.fallbackID
        )
        // Only live games: the demo and a Duos lobby (the log sees no Solo leaderboard) say nothing useful.
        if parsed.isBattlegrounds { diagnostics?.noteNameJoin(outcome.issues) }
        let players = outcome.players
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

    private var tavernNote: String {
        guard !tavernSheets.isEmpty, SettingsModel.showsTavernList() else { return "" }
        return tavernUsesLobbyTribes ? " · tavern list: lobby tribes" : " · tavern list: all tribes"
    }

    /// Once per game: the pool (cache or seed) is grouped for every tribe right away, then again for the
    /// lobby's own tribes when the reader finds them, and once more if a fresher pool was downloaded.
    private func refreshTavernIfNeeded(_ poll: LogPoll) {
        guard poll.lobby.isBattlegrounds, !poll.isGameOver, SettingsModel.showsTavernList() else { return }
        if poll.gamesStarted != tavernGame {
            tavernGame = poll.gamesStarted
            lobbyTribes = nil
            lobbyRaceTries = 0
            lobbyRaceReadAt = nil
            lobbyRaceTask?.cancel()
            lobbyRaceTask = nil
            tavernTask?.cancel()
            let game = tavernGame
            tavernTask = Task { [weak self, tavernPool] in
                let cards = await tavernPool.cards()
                await self?.buildTavern(cards, game: game)
                if let fresh = await tavernPool.refreshIfDue() { await self?.buildTavern(fresh, game: game) }
            }
        }
        readLobbyTribesIfNeeded(poll)
    }

    /// The lobby's tribes come from the game reader, a few tries a few seconds apart; without them the list
    /// keeps every tribe.
    private func readLobbyTribesIfNeeded(_ poll: LogPoll) {
        guard lobbyTribes == nil, lobbyRaceTask == nil, lobbyRaceTries < 10, poll.mirror != nil,
              SettingsModel.readsTribesFromMemory(),
              lobbyRaceReadAt.map({ Date().timeIntervalSince($0) >= 3 }) ?? true else { return }
        lobbyRaceTries += 1
        lobbyRaceReadAt = Date()
        let game = tavernGame
        lobbyRaceTask = Task { [weak self, poller] in
            let ids = await poller.lobbyRaces()
            guard let self, !Task.isCancelled, game == self.tavernGame else { return }
            self.lobbyRaceTask = nil
            guard let tribes = ids.flatMap(TavernList.lobbyTribes(fromRaceIDs:)) else { return }
            self.lobbyTribes = tribes
            let cards = await self.tavernPool.cards()
            await self.buildTavern(cards, game: game)
        }
    }

    private func buildTavern(_ cards: [PoolCard], game: Int) async {
        let tribes = lobbyTribes
        let sheets = await Task.detached(priority: .userInitiated) {
            TavernList.sheets(pool: cards, lobbyTribes: tribes)
        }.value
        guard game == tavernGame, !Task.isCancelled else { return }
        tavernUsesLobbyTribes = tribes != nil
        if sheets != tavernSheets { tavernSheets = sheets }
    }

    /// Demo: the list for a made-up five-tribe lobby, built like a real one.
    func loadDemoTavern() {
        guard tavernSheets.isEmpty else { return }
        let tribes: Set<String> = ["BEAST", "DRAGON", "MECHANICAL", "PIRATE", "UNDEAD"]
        tavernGame = 0
        lobbyTribes = tribes
        Task { [weak self, tavernPool] in
            let cards = await tavernPool.cards()
            await self?.buildTavern(cards, game: 0)
        }
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
