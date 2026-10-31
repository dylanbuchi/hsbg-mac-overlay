import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@main
struct HSBGMacOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: .shared)
        }
    }
}
