import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlayWindow: NSPanel?
    private var legendWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusMenuItem: NSMenuItem?
    private var lobbyMenuItem: NSMenuItem?
    private var positionTimer: Timer?
    private let overlayModel = OverlayModel()
    private var updateMenuItem: NSMenuItem?
    private var fixLoggingMenuItem: NSMenuItem?
    private var availableUpdate: ReleaseInfo?

    private var demoWindow: NSWindow?
    private var minionZoom: MinionZoomController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DemoMode.isRequested() {
            showDemo()
            return
        }
        NSApp.setActivationPolicy(.accessory)
        registerWorkspaceObservers()
        configureStatusItem()
        if hearthstoneIsRunning {
            showOverlay()
        }
        // The app has no window, so the first launch shows the guide once.
        if !UserDefaults.standard.bool(forKey: "didShowLegend") {
            UserDefaults.standard.set(true, forKey: "didShowLegend")
            showLegend()
        }
        Task {
            guard SettingsModel.shouldCheckForUpdates(),
                  let release = await UpdateChecker.fetchLatest(),
                  UpdateChecker.isNewer(release.version, than: AppInfo.version) else { return }
            availableUpdate = release
        }
    }

    private func showDemo() {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentViewController: NSHostingController(rootView: DemoRoot(model: overlayModel)))
        window.title = "HSBG Mac Overlay · demo"
        window.setContentSize(NSSize(width: 2000, height: 1170))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        demoWindow = window
        // The demo canvas is the top of the window's content, above the control bar.
        let zoom = MinionZoomController(model: overlayModel) { [weak self, weak window] in
            guard let window, let content = window.contentView, let size = self?.overlayModel.canvasSize, size.width > 0 else { return nil }
            let screen = window.convertToScreen(content.frame)
            return CGRect(x: screen.minX, y: screen.maxY - size.height, width: size.width, height: size.height)
        }
        zoom.start()
        minionZoom = zoom
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
        minionZoom?.stop()
        minionZoom = nil
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
        let lobbyLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lobbyLine.isEnabled = false
        lobbyLine.isHidden = true
        menu.addItem(lobbyLine)
        lobbyMenuItem = lobbyLine
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
        let combatItem = NSMenuItem(title: "Show Overlay During Combat", action: #selector(toggleHideDuringCombat(_:)), keyEquivalent: "")
        combatItem.target = self
        combatItem.state = overlayModel.hidesDuringCombat ? .off : .on
        menu.addItem(combatItem)
        let cardCombatItem = NSMenuItem(title: "Show Next Opponent During Combat", action: #selector(toggleCardInCombat(_:)), keyEquivalent: "")
        cardCombatItem.target = self
        cardCombatItem.state = overlayModel.showsCardInCombat ? .on : .off
        menu.addItem(cardCombatItem)
        menu.addItem(.separator())
        let legendItem = NSMenuItem(title: "How to Read the Overlay…", action: #selector(showLegend), keyEquivalent: "")
        legendItem.target = self
        menu.addItem(legendItem)
        let fixItem = NSMenuItem(title: "Turn On Power Logging…", action: #selector(fixPowerLogging), keyEquivalent: "")
        fixItem.target = self
        fixItem.isHidden = true
        menu.addItem(fixItem)
        fixLoggingMenuItem = fixItem
        let updateItem = NSMenuItem(title: "New Version Available", action: #selector(openReleasePage), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        updateMenuItem = updateItem
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let aboutItem = NSMenuItem(title: "About HSBG Mac Overlay", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let versionItem = NSMenuItem(title: AboutInfo.versionLine(), action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuItem?.title = overlayModel.status
        lobbyMenuItem?.title = overlayModel.lobbySummary
        lobbyMenuItem?.isHidden = overlayModel.lobbySummary.isEmpty
        let config = try? String(contentsOf: PowerLogConfig.url, encoding: .utf8)
        fixLoggingMenuItem?.isHidden = !PowerLogConfig.needsFix(config)
        if let release = availableUpdate {
            updateMenuItem?.title = "New Version Available: \(release.version)…"
            updateMenuItem?.isHidden = false
        }
    }

    @objc private func openReleasePage() {
        if let url = availableUpdate?.url { NSWorkspace.shared.open(url) }
    }

    @objc private func fixPowerLogging() {
        let alert = NSAlert()
        alert.messageText = "Turn on Power logging?"
        alert.informativeText = "This sets the [Power] section of \(PowerLogConfig.url.path) so Hearthstone writes the log the overlay reads. "
            + "The old file is kept as log.config.bak. Restart Hearthstone afterwards."
        alert.addButton(withTitle: "Update log.config")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try PowerLogConfig.apply()
            let done = NSAlert()
            done.messageText = "log.config updated"
            done.informativeText = "Restart Hearthstone for the change to take effect."
            done.runModal()
        } catch {
            let failed = NSAlert()
            failed.messageText = "Could not update log.config"
            failed.informativeText = error.localizedDescription
            failed.runModal()
        }
    }

    @objc private func showOverlayFromMenu() {
        showOverlay()
    }

    @objc private func showAbout() {
        // A menu-bar app is never frontmost on its own.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "HSBG Mac Overlay",
            .applicationVersion: AppInfo.version,
            .version: "",
            .credits: AboutInfo.credits()
        ])
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

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: .shared)))
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleTierIcons(_ sender: NSMenuItem) {
        overlayModel.showsTierIcons.toggle()
        sender.state = overlayModel.showsTierIcons ? .on : .off
    }

    @objc private func toggleHideDuringCombat(_ sender: NSMenuItem) {
        overlayModel.hidesDuringCombat.toggle()
        sender.state = overlayModel.hidesDuringCombat ? .off : .on
    }

    @objc private func toggleCardInCombat(_ sender: NSMenuItem) {
        overlayModel.showsCardInCombat.toggle()
        sender.state = overlayModel.showsCardInCombat ? .on : .off
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
        let zoom = MinionZoomController(model: overlayModel) { [weak self] in
            guard let window = self?.overlayWindow, window.isVisible else { return nil }
            return window.frame
        }
        zoom.start()
        minionZoom = zoom
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(updateOverlayPosition),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
        updateOverlayPosition()
    }

    @objc private func updateOverlayPosition() {
        guard let panel = overlayWindow,
              hearthstoneIsRunning,
              hearthstoneIsFrontmost,
              let hearthstoneFrame = HearthstoneWindowLocator.cocoaFrame else {
            overlayWindow?.orderOut(nil)
            minionZoom?.hide()
            return
        }
        // Cover the game's content area so tags are never clipped; the panel ignores clicks.
        panel.setFrame(hearthstoneFrame, display: true)
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? hearthstoneFrame.maxY
        let trackerFrames = HSTrackerWindowLocator.frames.map {
            CanvasCoordinates.canvasFrame(fromGlobal: $0, canvasCocoaFrame: hearthstoneFrame, primaryScreenMaxY: primaryMaxY)
        }
        overlayModel.setTrackerPanel(TrackerPanelPicker.leftPanel(among: trackerFrames, canvas: hearthstoneFrame.size))
        panel.orderFrontRegardless()
        minionZoom?.refresh()
    }
}
