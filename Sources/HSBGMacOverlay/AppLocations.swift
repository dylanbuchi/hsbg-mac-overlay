import AppKit
import Foundation
import Security

/// Finds HSTracker and Hearthstone wherever they are installed, falling back to /Applications.
enum AppLocations {
    static let hstrackerBundleID = "net.hearthsim.hstracker"

    private static let frameworkRelativePath = "Contents/Frameworks/HearthMirror.framework/HearthMirror"
    private static let fallbackHSTracker = URL(fileURLWithPath: "/Applications/HSTracker.app")

    /// LaunchServices can return a stale copy (an old download), so a hit without
    /// HearthMirror inside is ignored in favour of /Applications.
    static func hstrackerURL(
        resolve: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        if let found = resolve(hstrackerBundleID),
           fileExists(found.appendingPathComponent(frameworkRelativePath).path) {
            return found
        }
        return fallbackHSTracker
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedHSTracker: URL?

    /// Resolved once a copy with HearthMirror is found, so rendering never queries LaunchServices repeatedly.
    static var hstracker: URL {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedHSTracker { return cachedHSTracker }
        let url = hstrackerURL()
        if FileManager.default.fileExists(atPath: url.appendingPathComponent(frameworkRelativePath).path) {
            cachedHSTracker = url
        }
        return url
    }

    /// Tier shields and tribe pictures are only taken from HearthSim's signed HSTracker.
    /// Anything else fails closed (drawn icons instead).
    static func isGenuineHSTracker(at appURL: URL) -> Bool {
        let requirementText = "anchor apple generic and identifier \"\(hstrackerBundleID)\""
            + " and certificate leaf[subject.OU] = \"RL7C49LAMC\""
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    static var tierIconsDirectory: String {
        hstracker.appendingPathComponent("Contents/Resources/Resources/Battlegrounds").path
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
