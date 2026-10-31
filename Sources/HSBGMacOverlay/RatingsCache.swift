import Foundation

/// The last good leaderboard, kept across launches so a rating lookup can survive every source being down.
/// The file is only ever a fallback: it expires, and whatever it holds is re-validated on load.
struct RatingsCache: Sendable {
    static let maxAge: TimeInterval = 6 * 60 * 60
    static let minimumEntries = 50
    private static let maxEntries = 100_000
    private static let maxFileBytes = 20 * 1024 * 1024

    struct Entry: Equatable, Sendable {
        let ratings: [String: Int]
        let source: String
        let savedAt: Date
    }

    private struct File: Codable {
        var version: Int
        var region: String
        var source: String
        var savedAt: Date
        var ratings: [String: Int]
    }

    let directory: URL
    var now: @Sendable () -> Date = { Date() }

    static var standard: RatingsCache? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return RatingsCache(directory: support.appendingPathComponent("HSBGMacOverlay", isDirectory: true))
    }

    private func fileURL(_ region: LeaderboardRegion) -> URL {
        directory.appendingPathComponent("ratings-\(region.rawValue).json")
    }

    func save(_ ratings: [String: Int], region: LeaderboardRegion, source: String) {
        guard Self.isPlausible(ratings) else { return }
        let file = File(version: 1, region: region.rawValue, source: source, savedAt: now(), ratings: ratings)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(region), options: .atomic)
    }

    func load(region: LeaderboardRegion) -> Entry? {
        let url = fileURL(region)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= Self.maxFileBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let file = try? decoder.decode(File.self, from: data),
              file.version == 1, file.region == region.rawValue,
              file.savedAt <= now().addingTimeInterval(60),
              now().timeIntervalSince(file.savedAt) <= Self.maxAge,
              Self.isPlausible(file.ratings) else { return nil }
        return Entry(ratings: file.ratings, source: file.source, savedAt: file.savedAt)
    }

    /// Guards against truncated pages and corrupted files: enough rows, sane values.
    static func isPlausible(_ ratings: [String: Int]) -> Bool {
        ratings.count >= minimumEntries && ratings.count <= maxEntries
            && ratings.allSatisfy { $0.key.count <= 64 && (0...100_000).contains($0.value) }
    }
}
