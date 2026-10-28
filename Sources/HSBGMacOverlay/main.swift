import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@main
struct HSBGMacOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

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
    private var parser = PowerLogParser()
    private let hearthMirror = HearthMirrorBridge()
    private var mirrorSnapshot: HearthMirrorLobbySnapshot?
    private var mirrorGameUUID: String?
    private var mirrorOrder: [String] = []
    private var ratings: [String: Int] = [:]
    private var lastRatingAttempt: Date?
    private var leaderboardClient = LeaderboardClient(
        region: LeaderboardRegion(rawValue: UserDefaults.standard.string(forKey: "region") ?? "") ?? .eu
    )
    private var currentLogURL: URL?
    private var fileOffset: UInt64 = 0
    /// Bytes after the last newline; a read can end in the middle of a multi-byte character.
    private var pendingBytes = Data()

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
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
        ratings.removeAll()
        lastRatingAttempt = nil
        publishLobby()
    }

    var region: LeaderboardRegion {
        leaderboardClient.region
    }

    @objc private func refreshTimerFired() {
        refresh()
    }

    private func refresh() {
        guard let url = HearthstoneLogLocator.newestPowerLog else {
            status = "No Power.log yet: enable Power logging (see README) and restart Hearthstone"
            return
        }

        if currentLogURL != url {
            currentLogURL = url
            fileOffset = 0
            pendingBytes = Data()
            parser = PowerLogParser()
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.seek(toOffset: fileOffset)
            let data = try handle.readToEnd() ?? Data()
            fileOffset = handle.offsetInFile
            try handle.close()
            consume(data)
            mirrorSnapshot = hearthMirror.readLobby()
            if mirrorSnapshot == nil {
                mirrorGameUUID = nil
                mirrorOrder.removeAll()
            }
            publishLobby(parsed: parser.snapshot())
            showsTags = lobby.isBattlegrounds && !parser.isGameOver
                && !(hidesDuringCombat && parser.isInCombat)
            let place = parser.nextOpponentPlace ?? 0
            if place != nextOpponentPlace {
                nextOpponentPlace = place
            }
            if parser.turn != turn {
                turn = parser.turn
            }
            refreshRatingsIfNeeded()
            let source: String
            switch hearthMirror.lastError {
            case "live": source = "names from HSTracker"
            // The lobby only exists once a match is found.
            case "HearthMirror lobby unavailable", "HearthMirror returned no players": source = "waiting for lobby names"
            default: source = "no names: \(hearthMirror.lastError)"
            }
            if parser.isDuos {
                status = "Duos is not supported yet"
            } else if parser.isGameOver {
                status = "Game over · waiting for the next match"
            } else if lobby.isBattlegrounds {
                status = "Connected · \(lobby.players.count) players · MMR \(leaderboardClient.region.rawValue) · \(source)"
            } else {
                status = "Log connected · waiting for a Battlegrounds Solo match"
            }
        } catch {
            showsTags = false
            status = "Could not read Power.log"
        }
    }

    private func publishLobby(parsed: BattlegroundsLobby? = nil) {
        var updated = parsed ?? parser.snapshot()
        if let mirrorSnapshot {
            updated = merge(mirrorSnapshot, with: updated)
        }
        for index in updated.players.indices {
            updated.players[index].rating = ratings[updated.players[index].name]
        }
        lobby = updated
    }

    private func merge(_ mirror: HearthMirrorLobbySnapshot, with parsed: BattlegroundsLobby) -> BattlegroundsLobby {
        let identities = mirror.players.map(identity(for:))
        if mirrorGameUUID != mirror.gameUUID || shouldResetMirrorOrder(for: identities) {
            mirrorGameUUID = mirror.gameUUID
            mirrorOrder = identities
        } else {
            mirrorOrder = StableLobbyOrder.update(existing: mirrorOrder, incoming: identities)
        }

        // Identities can repeat while the lobby is still loading (e.g. account 0:0).
        let mirrorByIdentity = Dictionary(mirror.players.map { (identity(for: $0), $0) },
                                          uniquingKeysWith: { first, _ in first })
        let orderedMirrorPlayers = mirrorOrder.compactMap { identity in
            mirrorByIdentity[identity].map { (identity: identity, player: $0) }
        }
        let players = LeaderboardMerge.players(
            mirrorPlayers: orderedMirrorPlayers,
            parsed: parsed.players,
            localPlayerName: mirror.localPlayerName,
            fallbackID: playersFallbackID
        )
        // The mirror also has a lobby in Duos; the log decides whether this is a Solo match.
        return BattlegroundsLobby(isBattlegrounds: parsed.isBattlegrounds, players: players)
    }

    private func identity(for player: HearthMirrorLobbySnapshot.Player) -> String {
        if !player.accountID.isEmpty && player.accountID != ":" {
            return "account:\(player.accountID)"
        }
        if !player.heroCardID.isEmpty {
            return "hero:\(player.heroCardID)"
        }
        return "name:\(player.name)"
    }

    private func shouldResetMirrorOrder(for incoming: [String]) -> Bool {
        guard !mirrorOrder.isEmpty else { return true }
        let overlap = Set(mirrorOrder).intersection(incoming).count
        return overlap < max(1, min(3, incoming.count / 2))
    }

    private func playersFallbackID(_ identity: String) -> Int {
        abs(identity.hashValue) % 1_000_000 + 1
    }

    private func refreshRatingsIfNeeded() {
        guard lobby.isBattlegrounds,
              !lobby.players.filter({ !$0.isLocalPlayer && !$0.name.isEmpty }).isEmpty,
              ratingTask == nil,
              Date().timeIntervalSince(lastRatingAttempt ?? .distantPast) >= 15 * 60 else { return }

        lastRatingAttempt = Date()
        ratingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let freshRatings = try await leaderboardClient.fetchRatings()
                guard !Task.isCancelled else { return }
                ratings = freshRatings
                publishLobby()
            } catch {
                // Local log data remains useful when the optional lookup is offline.
            }
            ratingTask = nil
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        pendingBytes.append(data)
        // Split on newline bytes and decode whole lines only, so names in any script survive.
        guard let lastNewline = pendingBytes.lastIndex(of: 0x0A) else { return }
        let complete = pendingBytes[pendingBytes.startIndex...lastNewline]
        pendingBytes = Data(pendingBytes[pendingBytes.index(after: lastNewline)...])
        for line in complete.split(separator: 0x0A) {
            parser.feed(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .newlines))
        }
    }
}

enum HearthstoneLogLocator {
    private static let roots = [
        URL(fileURLWithPath: "/Applications/Hearthstone/Logs"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hearthstone")
    ]

    static var newestPowerLog: URL? {
        let candidates = roots.flatMap { root -> [(URL, Date)] in
            guard let folders = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return folders.compactMap { folder in
                guard folder.lastPathComponent.hasPrefix("Hearthstone_") else { return nil }
                let log = folder.appendingPathComponent("Power.log")
                guard let values = try? log.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate else { return nil }
                return (log, modified)
            }
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlayWindow: NSPanel?
    private var legendWindow: NSWindow?
    private var statusMenuItem: NSMenuItem?
    private var positionTimer: Timer?
    private let overlayModel = OverlayModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerWorkspaceObservers()
        configureStatusItem()
        if hearthstoneIsRunning {
            showOverlay()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        positionTimer?.invalidate()
        overlayWindow?.close()
    }

    private var hearthstoneIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains(where: isHearthstone)
    }

    private var hearthstoneIsFrontmost: Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else { return false }
        return isHearthstone(application)
    }

    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(hearthstoneLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(hearthstoneTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    private func isHearthstone(_ application: NSRunningApplication) -> Bool {
        application.localizedName == "Hearthstone"
            || application.bundleURL?.lastPathComponent == "Hearthstone.app"
    }

    @objc private func hearthstoneLaunched(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              isHearthstone(application) else { return }
        showOverlay()
    }

    @objc private func hearthstoneTerminated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              isHearthstone(application) else { return }
        positionTimer?.invalidate()
        positionTimer = nil
        overlayWindow?.close()
        overlayWindow = nil
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "BG"

        let menu = NSMenu()
        menu.delegate = self
        // What the overlay currently sees, so a silent overlay explains itself.
        let statusLine = NSMenuItem(title: overlayModel.status, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        statusMenuItem = statusLine
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Overlay", action: #selector(showOverlayFromMenu), keyEquivalent: ""))
        let regionItem = NSMenuItem(title: "MMR Region", action: nil, keyEquivalent: "")
        let regionMenu = NSMenu()
        for region in LeaderboardRegion.allCases {
            let item = NSMenuItem(title: region.rawValue, action: #selector(selectRegion(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = region.rawValue
            item.state = region == overlayModel.region ? .on : .off
            regionMenu.addItem(item)
        }
        regionItem.submenu = regionMenu
        menu.addItem(regionItem)
        let tierIconsItem = NSMenuItem(title: "Tier Icons", action: #selector(toggleTierIcons(_:)), keyEquivalent: "")
        tierIconsItem.target = self
        tierIconsItem.state = overlayModel.showsTierIcons ? .on : .off
        menu.addItem(tierIconsItem)
        let combatItem = NSMenuItem(title: "Hide During Combat", action: #selector(toggleHideDuringCombat(_:)), keyEquivalent: "")
        combatItem.target = self
        combatItem.state = overlayModel.hidesDuringCombat ? .on : .off
        menu.addItem(combatItem)
        menu.addItem(.separator())
        let legendItem = NSMenuItem(title: "How to Read the Overlay…", action: #selector(showLegend), keyEquivalent: "")
        legendItem.target = self
        menu.addItem(legendItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuItem?.title = overlayModel.status
    }

    @objc private func showOverlayFromMenu() {
        showOverlay()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showLegend() {
        if legendWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: LegendView()))
            window.title = "How to Read the Overlay"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            legendWindow = window
        }
        // A menu-bar app is never frontmost on its own.
        NSApp.activate(ignoringOtherApps: true)
        legendWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleTierIcons(_ sender: NSMenuItem) {
        overlayModel.showsTierIcons.toggle()
        sender.state = overlayModel.showsTierIcons ? .on : .off
    }

    @objc private func toggleHideDuringCombat(_ sender: NSMenuItem) {
        overlayModel.hidesDuringCombat.toggle()
        sender.state = overlayModel.hidesDuringCombat ? .on : .off
    }

    @objc private func selectRegion(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let region = LeaderboardRegion(rawValue: rawValue) else { return }
        overlayModel.setRegion(region)
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
    }

    private func showOverlay() {
        guard hearthstoneIsRunning else { return }
        if overlayWindow != nil {
            updateOverlayPosition()
            return
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: InGameOverlayView(model: overlayModel))
        overlayWindow = panel
        positionTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(updateOverlayPosition),
            userInfo: nil,
            repeats: true
        )
        updateOverlayPosition()
    }

    @objc private func updateOverlayPosition() {
        guard let panel = overlayWindow,
              hearthstoneIsRunning,
              hearthstoneIsFrontmost,
              let hearthstoneFrame = HearthstoneWindowLocator.cocoaFrame else {
            overlayWindow?.orderOut(nil)
            return
        }
        // Cover the game's content area so tags are never clipped; the panel ignores clicks.
        panel.setFrame(hearthstoneFrame, display: true)
        panel.orderFrontRegardless()
    }
}

@MainActor
enum HearthstoneWindowLocator {
    static var cocoaFrame: NSRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            let owner = window[kCGWindowOwnerName as String] as? String
            guard owner == "Hearthstone",
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else { continue }
            let boundsDictionary = bounds as CFDictionary
            var cgFrame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &cgFrame),
                  cgFrame.width > 600,
                  cgFrame.height > 400 else { continue }

            let screenHeight = NSScreen.screens.first?.frame.maxY ?? cgFrame.maxY
            let frame = NSRect(
                x: cgFrame.minX,
                y: screenHeight - cgFrame.maxY,
                width: cgFrame.width,
                height: cgFrame.height
            )
            // In a window, the leaderboard geometry is relative to the content
            // area below the title bar, as in HSTracker's SizeHelper.
            let isFullscreen = NSScreen.screens.contains { $0.frame == frame }
            guard !isFullscreen else { return frame }
            return NSRect(x: frame.minX, y: frame.minY,
                          width: frame.width, height: max(frame.height - titlebarHeight, 0))
        }
        return nil
    }

    private static let titlebarHeight: CGFloat = {
        let content = NSRect(x: 0, y: 0, width: 100, height: 100)
        return NSWindow.frameRect(forContentRect: content, styleMask: [.titled]).height - content.height
    }()
}

private struct InGameOverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        GeometryReader { geometry in
            let layout = LeaderboardLayout(canvasSize: geometry.size,
                                           nextOpponentPlace: model.nextOpponentPlace)
            let tile = layout.tileHeight
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(model.lobby.players.enumerated()), id: \.element.id) { index, player in
                    let slot = (player.placement ?? index + 1) - 1
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
    private static let directory = "/Applications/HSTracker.app/Contents/Resources/Resources/Battlegrounds"
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

