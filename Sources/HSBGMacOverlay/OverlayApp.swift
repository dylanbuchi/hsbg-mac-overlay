import AppKit

/// Plain AppKit entry point. A SwiftUI `App` needs at least one scene, and even a `Settings`
/// scene can open its window at launch in a menu-bar app; the Settings window is owned by
/// `AppDelegate` instead, so no window exists until the user asks for one.
@main
@MainActor
enum HSBGMacOverlayApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
