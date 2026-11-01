import Foundation
import ServiceManagement
import SwiftUI

enum LoginItemState: Equatable {
    case enabled, disabled, requiresApproval, unavailable
}

/// The slice of `SMAppService` the settings use, so tests can inject a fake.
@MainActor
protocol LoginItemControlling {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItem: LoginItemControlling {
    private var service: SMAppService { .mainApp }

    var state: LoginItemState {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        default: return .unavailable
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
}

enum SettingsKey {
    static let checksForUpdates = "checksForUpdates"
    static let readsTribesFromMemory = "readsTribesFromMemory"
    static let zoomsMinionsOnHover = "zoomsMinionsOnHover"
}

@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    /// What the system says right now, not what was last clicked.
    @Published private(set) var launchAtLogin: Bool
    /// Why the last change did not take, or a hint to approve the app; nil when all is well.
    @Published private(set) var loginMessage: String?
    @Published var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: SettingsKey.checksForUpdates) }
    }

    @Published var readsTribesFromMemory: Bool {
        didSet { defaults.set(readsTribesFromMemory, forKey: SettingsKey.readsTribesFromMemory) }
    }

    @Published var zoomsMinionsOnHover: Bool {
        didSet { defaults.set(zoomsMinionsOnHover, forKey: SettingsKey.zoomsMinionsOnHover) }
    }

    private let defaults: UserDefaults
    private let loginItem: LoginItemControlling

    init(defaults: UserDefaults = .standard, loginItem: LoginItemControlling = SystemLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        checksForUpdates = Self.shouldCheckForUpdates(defaults)
        readsTribesFromMemory = Self.readsTribesFromMemory(defaults)
        zoomsMinionsOnHover = Self.zoomsMinionsOnHover(defaults)
        launchAtLogin = loginItem.state == .enabled
        loginMessage = Self.message(for: loginItem.state)
    }

    /// Default on: the key is only ever written when the user flips the toggle.
    nonisolated static func shouldCheckForUpdates(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.checksForUpdates) as? Bool ?? true
    }

    /// Default on: live opponent tribes come from reading game memory through HSTracker's HearthMirror.
    nonisolated static func readsTribesFromMemory(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.readsTribesFromMemory) as? Bool ?? true
    }

    /// Default on: hovering a minion in the card's last board shows it larger.
    nonisolated static func zoomsMinionsOnHover(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.zoomsMinionsOnHover) as? Bool ?? true
    }

    /// Call when the window opens: the user may have changed Login Items in System Settings.
    func refresh() {
        launchAtLogin = loginItem.state == .enabled
        loginMessage = Self.message(for: loginItem.state)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if loginItem.state != .enabled { try loginItem.register() }
            } else if loginItem.state != .disabled {
                try loginItem.unregister()
            }
            launchAtLogin = loginItem.state == .enabled
            loginMessage = Self.message(for: loginItem.state)
        } catch {
            launchAtLogin = loginItem.state == .enabled
            loginMessage = "macOS did not accept this change (\(error.localizedDescription)). "
                + "This app is not notarized, so you can also add it yourself in System Settings > General > Login Items."
        }
    }

    private static func message(for state: LoginItemState) -> String? {
        switch state {
        case .requiresApproval:
            return "Allow HSBG Mac Overlay in System Settings > General > Login Items."
        case .unavailable:
            return "Launch at login is not available for this copy. Move the app to Applications and try again."
        case .enabled, .disabled:
            return nil
        }
    }

    static func versionLine(version: String = AppInfo.version, build: String? = AppInfo.build) -> String {
        guard let build, !build.isEmpty else { return AboutInfo.versionLine(version) }
        return "\(AboutInfo.versionLine(version)) (build \(build))"
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let message = model.loginMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Check for updates automatically", isOn: $model.checksForUpdates)
                Text("One anonymous request to GitHub at launch. A newer version only adds a menu item.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Read opponent tribes from game memory", isOn: $model.readsTribesFromMemory)
                Text("Only reads what the game already shows in its leaderboard hover.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Zoom minions on hover", isOn: $model.zoomsMinionsOnHover)
                Text("Point at a minion in the card's last board to see it larger. Only watches where the mouse is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text(SettingsModel.versionLine())
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 400, alignment: .leading)
        .onAppear { model.refresh() }
    }
}
