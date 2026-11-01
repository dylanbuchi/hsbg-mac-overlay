import AppKit
import Darwin
import Foundation
import TribeMemory

struct HearthMirrorLobbySnapshot: Sendable {
    struct Player: Sendable {
        let name: String
        let heroCardID: String
        let accountID: String
    }

    let gameUUID: String?
    let players: [Player]
    let localPlayerName: String?
}

/// Source of the leaderboard tribe counts; the real one reads game memory, tests inject fakes.
protocol LeaderboardTribeReading {
    func readTribes() -> TribeReadResult
}

final class HearthMirrorBridge: LeaderboardTribeReading {
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var mirror: NSObject?
    private var processID: pid_t?
    private(set) var lastError = "not connected"
    private let hearthstonePID: () -> pid_t?
    private let hstrackerURL: () -> URL
    private let isGenuine: (URL) -> Bool
    /// Where the last signature check failed, so a rejected copy is not re-checked every second.
    private var rejection: (url: URL, stamp: [Date?])?

    /// The defaults talk to the real system; tests inject fakes and never reach HearthMirror.
    init(
        hearthstonePID: @escaping () -> pid_t? = {
            NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName == "Hearthstone" || $0.bundleURL?.lastPathComponent == "Hearthstone.app"
            })?.processIdentifier
        },
        hstrackerURL: @escaping () -> URL = { AppLocations.hstracker },
        isGenuine: @escaping (URL) -> Bool = AppLocations.isGenuineHSTracker(at:)
    ) {
        self.hearthstonePID = hearthstonePID
        self.hstrackerURL = hstrackerURL
        self.isGenuine = isGenuine
    }

    func readLobby() -> HearthMirrorLobbySnapshot? {
        guard let pid = hearthstonePID() else {
            mirror = nil
            processID = nil
            lastError = "Hearthstone not found"
            return nil
        }

        if processID != pid {
            mirror = nil
            processID = pid
        }

        // makeMirror and loadFramework set the specific reason when they fail.
        guard let mirror = mirror ?? makeMirror(for: pid) else { return nil }
        guard let lobby = send(mirror, "getBattlegroundsLobbyInfo"),
              let playerObjects = send(lobby, "players") as? [AnyObject] else {
            lastError = "HearthMirror lobby unavailable"
            return nil
        }

        let players = playerObjects.compactMap { player -> HearthMirrorLobbySnapshot.Player? in
            guard let name = send(player, "name") as? String, !name.isEmpty else { return nil }
            let heroCardID = (send(player, "heroCardId") as? String) ?? ""
            let account = send(player, "accountId")
            let lo = account.flatMap { send($0, "lo") as? NSNumber }?.stringValue ?? ""
            let hi = account.flatMap { send($0, "hi") as? NSNumber }?.stringValue ?? ""
            return .init(name: name, heroCardID: heroCardID, accountID: "\(hi):\(lo)")
        }

        guard !players.isEmpty else {
            lastError = "HearthMirror returned no players"
            return nil
        }

        let gameUUID = send(lobby, "gameUuid") as? String

        let matchInfo = send(mirror, "getMatchInfo")
        let localPlayer = matchInfo.flatMap { send($0, "localPlayer") }
        let localPlayerName = localPlayer.flatMap { send($0, "name") as? String }
        lastError = "live"
        return .init(gameUUID: gameUUID, players: players, localPlayerName: localPlayerName)
    }

    /// Read-only walk of the game's leaderboard tile data. Uses the connection `readLobby` already opened
    /// (same queue), so it never attaches to the game on its own.
    func readTribes() -> TribeReadResult {
        guard let mirror, let frameworkHandle, let pid = processID, hearthstonePID() == pid else {
            return .unavailable("not connected")
        }
        var reason: NSString?
        guard let raw = HSBGTribeMemory.read(withFramework: frameworkHandle, mirror: mirror, error: &reason) else {
            return .unavailable((reason as String?) ?? "read failed")
        }
        var counts: [Int: [Int: Int]] = [:]
        for (entity, races) in raw {
            counts[entity.intValue] = Dictionary(races.map { ($0.key.intValue, $0.value.intValue) },
                                                 uniquingKeysWith: { first, _ in first })
        }
        return .counts(counts)
    }

    private func makeMirror(for pid: pid_t) -> NSObject? {
        guard loadFramework() else { return nil }
        guard let mirrorClass = NSClassFromString("HearthMirror") as? NSObject.Type,
              let allocated = mirrorClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else {
            lastError = "HearthMirror framework unavailable"
            return nil
        }

        let selector = NSSelectorFromString("initWithPID:withBlocking:")
        guard allocated.responds(to: selector) else {
            lastError = "HearthMirror initializer unavailable"
            return nil
        }
        typealias InitMessage = @convention(c) (AnyObject, Selector, pid_t, Bool) -> AnyObject?
        let message = unsafeBitCast(allocated.method(for: selector), to: InitMessage.self)
        let initialized = message(allocated, selector, pid, false) as? NSObject
        if let initialized { mirror = initialized }
        if initialized == nil {
            lastError = "task_for_pid denied"
        }
        return initialized
    }

    private func loadFramework() -> Bool {
        if frameworkHandle != nil { return true }
        let url = hstrackerURL()
        let stamp = Self.stamp(of: url)
        if let rejection, rejection.url == url, rejection.stamp == stamp {
            lastError = Self.rejectedMessage
            return false
        }
        guard isGenuine(url) else {
            rejection = (url, stamp)
            lastError = Self.rejectedMessage
            return false
        }
        rejection = nil
        frameworkHandle = dlopen(AppLocations.hearthMirrorFrameworkPath, RTLD_NOW | RTLD_LOCAL)
        if frameworkHandle == nil {
            lastError = "could not load HearthMirror"
        }
        return frameworkHandle != nil
    }

    private static let rejectedMessage = "HSTracker is missing or its signature is not HearthSim's"

    /// Changes when HSTracker is replaced or updated, which is when a rejection should be retried.
    private static func stamp(of appURL: URL) -> [Date?] {
        [appURL, appURL.appendingPathComponent("Contents/Info.plist"),
         appURL.appendingPathComponent("Contents/Frameworks/HearthMirror.framework/HearthMirror")].map {
            // FileManager, not URL resource values: those are cached on the URL object.
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }
    }

    private func send(_ object: AnyObject, _ selectorName: String) -> AnyObject? {
        guard let object = object as? NSObject else { return nil }
        let selector = Selector(selectorName)
        guard object.responds(to: selector) else { return nil }
        typealias Message = @convention(c) (AnyObject, Selector) -> AnyObject?
        let message = unsafeBitCast(object.method(for: selector), to: Message.self)
        return message(object, selector)
    }
}
