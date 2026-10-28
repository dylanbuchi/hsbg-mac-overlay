import AppKit
import Darwin
import Foundation

struct HearthMirrorLobbySnapshot {
    struct Player {
        let name: String
        let heroCardID: String
        let accountID: String
    }

    let gameUUID: String?
    let players: [Player]
    let localPlayerName: String?
}

final class HearthMirrorBridge {
    private static let frameworkPath = "/Applications/HSTracker.app/Contents/Frameworks/HearthMirror.framework/HearthMirror"

    private var frameworkHandle: UnsafeMutableRawPointer?
    private var mirror: NSObject?
    private var processID: pid_t?
    private(set) var lastError = "not connected"

    func readLobby() -> HearthMirrorLobbySnapshot? {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == "Hearthstone" || $0.bundleURL?.lastPathComponent == "Hearthstone.app"
        }) else {
            mirror = nil
            processID = nil
            lastError = "Hearthstone not found"
            return nil
        }

        let pid = application.processIdentifier
        if processID != pid {
            mirror = nil
            processID = pid
        }

        guard let mirror = mirror ?? makeMirror(for: pid),
              let lobby = send(mirror, "getBattlegroundsLobbyInfo"),
              let playerObjects = send(lobby, "players") as? [AnyObject] else {
            if self.mirror == nil {
                lastError = "HearthMirror could not attach to Hearthstone"
            } else {
                lastError = "HearthMirror lobby unavailable"
            }
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

    private func makeMirror(for pid: pid_t) -> NSObject? {
        guard loadFramework(),
              let mirrorClass = NSClassFromString("HearthMirror") as? NSObject.Type,
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
        frameworkHandle = dlopen(Self.frameworkPath, RTLD_NOW | RTLD_LOCAL)
        if frameworkHandle == nil {
            lastError = "could not load HearthMirror"
        }
        return frameworkHandle != nil
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
