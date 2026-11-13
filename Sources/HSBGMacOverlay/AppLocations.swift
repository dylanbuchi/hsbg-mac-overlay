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

    static var hearthMirrorFrameworkPath: String {
        hstracker.appendingPathComponent(frameworkRelativePath).path
    }

    /// The framework is loaded into a process that may read Hearthstone's memory, so only
    /// HearthSim's signed HSTracker is accepted. Anything else fails closed (log-only mode).
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

    /// Text HearthMirror prints when it refuses any app but HSTracker (HSTracker 3.7.4 and newer).
    static let hstrackerOnlyMarker = Data("licensed for use by HSTracker only".utf8)

    /// True when the installed HearthMirror only works inside HSTracker. Read-only scan of the
    /// framework file; it is never loaded for this check.
    static func hearthMirrorIsHSTrackerOnly(at appURL: URL) -> Bool {
        let binary = appURL.appendingPathComponent(frameworkRelativePath)
        guard let data = try? Data(contentsOf: binary, options: .mappedIfSafe) else { return false }
        return data.range(of: hstrackerOnlyMarker) != nil
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
