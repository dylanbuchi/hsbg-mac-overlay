import AppKit
import CoreGraphics
import Foundation
import SwiftUI

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
            return
        }
        // Cover the game's content area so tags are never clipped; the panel ignores clicks.
        panel.setFrame(hearthstoneFrame, display: true)
        panel.orderFrontRegardless()
    }
}
