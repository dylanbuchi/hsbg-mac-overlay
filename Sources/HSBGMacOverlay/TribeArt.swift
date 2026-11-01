import AppKit

/// Where tribe pictures come from: the user's own, genuine HSTracker install. They are Blizzard art inside
/// HearthSim's app, so they are only displayed from there, never copied, extracted or bundled here.
struct TribeArtSource {
    /// HearthSim's signed build is installed (checked before anything is loaded from it).
    var isGenuine: () -> Bool
    /// The named image from HSTracker's asset catalog, e.g. `tribe_beast`.
    var load: (String) -> NSImage?

    static var hstracker: TribeArtSource { TribeArtSource(
        isGenuine: { AppLocations.isGenuineHSTracker(at: AppLocations.hstracker) },
        load: { name in Bundle(url: AppLocations.hstracker)?.image(forResource: name) }) }
}

/// Round tribe pictures as HSTracker's own panel shows them; nil sends callers to the drawn icon.
@MainActor
final class TribeArt {
    static let shared = TribeArt(source: .hstracker)
    static let retryAfter: TimeInterval = 60

    private let source: TribeArtSource
    private let now: () -> Date
    private var images: [String: NSImage] = [:]
    private var missing: Set<String> = []
    private var genuine = false
    private var rejectedAt: Date?

    init(source: TribeArtSource, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.now = now
    }

    /// Catalog name for a game race key ("BEAST" is `tribe_beast`); nil for a key without a picture.
    nonisolated static func assetName(for tribe: String) -> String? {
        TribeStyle.all[tribe] == nil ? nil : "tribe_" + tribe.lowercased()
    }

    func image(for tribe: String) -> NSImage? {
        guard let name = Self.assetName(for: tribe), !missing.contains(name) else { return nil }
        if let cached = images[name] { return cached }
        guard isAllowed else { return nil }
        guard let image = source.load(name) else {
            missing.insert(name)
            return nil
        }
        images[name] = image
        return image
    }

    /// The signature is checked once while it holds; a failure is re-checked a minute later, so an install
    /// that appears while the app runs is picked up without checking on every redraw.
    private var isAllowed: Bool {
        if genuine { return true }
        if let rejectedAt, now().timeIntervalSince(rejectedAt) < Self.retryAfter { return false }
        genuine = source.isGenuine()
        rejectedAt = genuine ? nil : now()
        return genuine
    }
}
