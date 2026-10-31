import AppKit
import Foundation

/// Finds HSTracker and Hearthstone wherever they are installed, falling back to /Applications.
enum AppLocations {
    static let hstrackerBundleID = "net.hearthsim.hstracker"

    static func hstrackerURL(
        resolve: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) -> URL {
        resolve(hstrackerBundleID) ?? URL(fileURLWithPath: "/Applications/HSTracker.app")
    }

    static var hearthMirrorFrameworkPath: String {
        hstrackerURL().appendingPathComponent("Contents/Frameworks/HearthMirror.framework/HearthMirror").path
    }

    static var tierIconsDirectory: String {
        hstrackerURL().appendingPathComponent("Contents/Resources/Resources/Battlegrounds").path
    }

    /// Folders that hold the `Hearthstone_*` log directories, most specific first.
    static func logRoots(hearthstoneApp: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var roots: [URL] = []
        if let hearthstoneApp {
            roots.append(hearthstoneApp.deletingLastPathComponent().appendingPathComponent("Logs"))
        }
        roots.append(URL(fileURLWithPath: "/Applications/Hearthstone/Logs"))
        roots.append(home.appendingPathComponent("Library/Logs/Hearthstone"))
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func runningHearthstoneURL() -> URL? {
        NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == "Hearthstone" || $0.bundleURL?.lastPathComponent == "Hearthstone.app"
        })?.bundleURL
    }
}
