import XCTest
@testable import HSBGMacOverlay

@MainActor
private final class FakeLoginItem: LoginItemControlling {
    struct Refused: LocalizedError { var errorDescription: String? { "refused" } }
    var state: LoginItemState
    var failure: Error?
    var onRegister: LoginItemState = .enabled
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(_ state: LoginItemState = .disabled) { self.state = state }

    func register() throws {
        registerCalls += 1
        if let failure { throw failure }
        state = onRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        if let failure { throw failure }
        state = .disabled
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "SettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testUpdateCheckIsOnByDefaultAndPersistsTheToggle() {
        let defaults = makeDefaults()
        XCTAssertTrue(SettingsModel.shouldCheckForUpdates(defaults))
        let model = SettingsModel(defaults: defaults, loginItem: FakeLoginItem())
        XCTAssertTrue(model.checksForUpdates)

        model.checksForUpdates = false
        XCTAssertFalse(SettingsModel.shouldCheckForUpdates(defaults))
        XCTAssertFalse(SettingsModel(defaults: defaults, loginItem: FakeLoginItem()).checksForUpdates)

        model.checksForUpdates = true
        XCTAssertTrue(SettingsModel.shouldCheckForUpdates(defaults))
    }

    func testLaunchAtLoginReflectsTheSystemState() {
        let model = SettingsModel(defaults: makeDefaults(), loginItem: FakeLoginItem(.enabled))
        XCTAssertTrue(model.launchAtLogin)
        XCTAssertNil(model.loginMessage)
    }

    func testEnablingAndDisablingRegistersThenUnregisters() {
        let item = FakeLoginItem(.disabled)
        let model = SettingsModel(defaults: makeDefaults(), loginItem: item)
        model.setLaunchAtLogin(true)
        XCTAssertTrue(model.launchAtLogin)
        XCTAssertEqual(item.registerCalls, 1)
        model.setLaunchAtLogin(true)
        XCTAssertEqual(item.registerCalls, 1, "already enabled: no second call")
        model.setLaunchAtLogin(false)
        XCTAssertFalse(model.launchAtLogin)
        XCTAssertEqual(item.unregisterCalls, 1)
        XCTAssertNil(model.loginMessage)
    }

    func testRegistrationFailureRevertsAndExplains() {
        let item = FakeLoginItem(.disabled)
        item.failure = FakeLoginItem.Refused()
        let model = SettingsModel(defaults: makeDefaults(), loginItem: item)
        model.setLaunchAtLogin(true)
        XCTAssertFalse(model.launchAtLogin)
        let message = model.loginMessage ?? ""
        XCTAssertTrue(message.contains("refused"))
        XCTAssertTrue(message.contains("Login Items"))
    }

    func testApprovalNeededShowsAHintAndStaysOff() {
        let item = FakeLoginItem(.disabled)
        item.onRegister = .requiresApproval
        let model = SettingsModel(defaults: makeDefaults(), loginItem: item)
        model.setLaunchAtLogin(true)
        XCTAssertFalse(model.launchAtLogin)
        XCTAssertTrue(model.loginMessage?.contains("System Settings") == true)
    }

    func testRefreshPicksUpChangesMadeInSystemSettings() {
        let item = FakeLoginItem(.disabled)
        let model = SettingsModel(defaults: makeDefaults(), loginItem: item)
        item.state = .enabled
        model.refresh()
        XCTAssertTrue(model.launchAtLogin)
        XCTAssertNil(model.loginMessage)
    }

    func testVersionLine() {
        XCTAssertEqual(SettingsModel.versionLine(version: "0.1.4", build: "7"), "Version 0.1.4 (build 7)")
        XCTAssertEqual(SettingsModel.versionLine(version: "0.1.4", build: nil), "Version 0.1.4")
    }
}
